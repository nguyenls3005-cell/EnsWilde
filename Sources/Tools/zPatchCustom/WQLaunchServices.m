//
//  WQLaunchServices.m
//  WQ Files
//  GPL-3.0-or-later.
//

#import "WQLaunchServices.h"
#include <sys/sysctl.h>
#import "WQLocalization.h"
#import "WQAccess.h"
#import <stdlib.h>
#import <string.h>
#import <sys/stat.h>

#pragma mark - App names from the LaunchServices database

// LaunchServices' own API refuses this app on 27.x (OSStatus -54) and the app
// bundles cannot be opened, but lsd keeps its database (CSStore2, magic
// "bdsl") in an Internal Daemon container that we can read. In it, Bundle
// records are 0x250 bytes long, preceded by [u32][u32 0x250]: +0x0c bundle
// id, +0x6c bundle name, +0x74 display name, each a string reference
// (string id << 2). Strings are stored as [u32 id][u32 length][UTF-8][NUL].
// Names that exist only in localized form (most Apple apps) are not decoded;
// the built-in table below covers those.

static NSString *const kWQLSStoreKey = @"WQLaunchServicesStore";
// When the database wasn't found: don't search again for a day (each search
// lists every daemon container), unless the user refreshes.
static NSString *const kWQLSMissKey = @"WQLaunchServicesStoreMissedAt";
static const NSTimeInterval kWQLSMissRetry = 24 * 60 * 60;

// These limits keep a malformed or unexpectedly large database from turning a
// synchronous display-name lookup into an unbounded read/parse operation.
static const size_t kWQLSMinStoreBytes = 0x1000;
static const size_t kWQLSMaxStoreBytes = 64u * 1024u * 1024u;
static const uint32_t kWQLSMaxStringID = 0x01000000u;
static const NSUInteger kWQLSMaxBundleRecords = 100000;
static const NSUInteger kWQLSMaxDecodedStrings = 200000;
static const NSUInteger kWQLSMaxDecodedStringBytes = 8u * 1024u * 1024u;

static NSObject *wq_ls_lock(void)
{
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

// The regression tests still exercise discovery through the daemon list.
#ifdef WQ_LS_TESTING
static BOOL wq_ls_test_daemon_search = YES;
void (^wq_ls_test_after_read)(NSString *path);
#else
static const BOOL wq_ls_test_daemon_search = NO;
#endif

static NSString *wq_find_ls_store(BOOL *searched);
static BOOL wq_ls_candidate_info(NSString *path, struct stat *st);

static BOOL wq_ls_stat_equal(const struct stat *a, const struct stat *b)
{
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
        a->st_size == b->st_size &&
        a->st_mtimespec.tv_sec == b->st_mtimespec.tv_sec &&
        a->st_mtimespec.tv_nsec == b->st_mtimespec.tv_nsec;
}

static NSDictionary *wq_ls_signature(const struct stat *st)
{
    return @{
        @"device": @(st->st_dev), @"inode": @(st->st_ino), @"size": @(st->st_size),
        @"modifiedSeconds": @(st->st_mtimespec.tv_sec),
        @"modifiedNanoseconds": @(st->st_mtimespec.tv_nsec)
    };
}

static BOOL wq_ls_signature_equal(NSDictionary *a, NSDictionary *b)
{
    return a && b && [a isEqualToDictionary:b];
}

static NSString *wq_ls_error(NSString *path, NSString *reason)
{
    return [NSString stringWithFormat:@"%@ (%@)", path ?: @"<none>", reason ?: @"unknown error"];
}

static BOOL wq_ls_candidate_info(NSString *path, struct stat *st)
{
    if (!path.length || !wq_stat(path, st) || !S_ISREG(st->st_mode) ||
        st->st_size < (off_t)kWQLSMinStoreBytes || st->st_size > (off_t)kWQLSMaxStoreBytes) {
        return NO;
    }
    NSString *error = nil;
    NSData *header = wq_read(path, 4, &error);
    if (header.length != 4 || memcmp(header.bytes, "bdsl", 4) != 0) return NO;
    return YES;
}

// Reads a store between two identical stats (device, inode, size, mtime), so
// a store rewritten while it was read is never parsed. Both the name loader
// and the container scan's store hints read through here.
static NSData *wq_ls_read_stable(NSString *path, struct stat *before, NSString **reason)
{
    if (!wq_ls_candidate_info(path, before)) { *reason = @"candidate is no longer valid"; return nil; }
    NSString *error = nil;
    NSData *data = wq_read(path, kWQLSMaxStoreBytes + 1, &error);
    if (!data || data.length > kWQLSMaxStoreBytes) { *reason = error ?: @"store exceeds size limit"; return nil; }
#ifdef WQ_LS_TESTING
    if (wq_ls_test_after_read) wq_ls_test_after_read(path);
#endif
    struct stat after;
    if (!wq_ls_candidate_info(path, &after) || !wq_ls_stat_equal(before, &after)) {
        *reason = @"store changed during read";
        return nil;
    }
    return data;
}

static BOOL wq_ls_is_newer(NSString *path, const struct stat *st,
                           NSString *bestPath, const struct stat *best)
{
    if (!bestPath) return YES;
    if (st->st_mtimespec.tv_sec != best->st_mtimespec.tv_sec)
        return st->st_mtimespec.tv_sec > best->st_mtimespec.tv_sec;
    if (st->st_mtimespec.tv_nsec != best->st_mtimespec.tv_nsec)
        return st->st_mtimespec.tv_nsec > best->st_mtimespec.tv_nsec;
    if (st->st_size != best->st_size) return st->st_size > best->st_size;
    return [path compare:bestPath] == NSOrderedAscending;
}

static void wq_ls_consider_candidate(NSString *path, NSString **bestPath,
                                      struct stat *best, NSMutableSet<NSString *> *seen)
{
    if (!path.length || [seen containsObject:path]) return;
    [seen addObject:path];

    struct stat st;
    if (!wq_ls_candidate_info(path, &st)) return;
    if (wq_ls_is_newer(path, &st, *bestPath, best)) {
        *bestPath = path;
        *best = st;
    }
}

// *searched: the daemon containers were actually listed (a failed or cancelled
// scan says nothing about whether the database exists).
static NSString *wq_find_ls_store(BOOL *searched)
{
    if (searched) *searched = NO;
    NSString *cached = [NSUserDefaults.standardUserDefaults stringForKey:kWQLSStoreKey];
    NSString *bestPath = nil;
    struct stat best = {0};
    struct stat cachedStat;
    BOOL cachedValid = cached.length && wq_ls_candidate_info(cached, &cachedStat);
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    if (cachedValid) wq_ls_consider_candidate(cached, &bestPath, &best, seen);

    // lsd's Caches folder can hold more than one store: an iOS update leaves
    // the old schema's file (the number in the name changes) next to the new
    // one. The newest file in the remembered folder is used, and the folder's
    // stores are logged once, so a Log shows which ones exist.
    if (cached.length) {
        NSString *caches = cached.stringByDeletingLastPathComponent;
        NSMutableArray<NSString *> *seenNames = [NSMutableArray new];
        for (NSString *name in [wq_list(caches, NULL) sortedArrayUsingSelector:@selector(compare:)]) {
            if (![name hasPrefix:@"com.apple.LaunchServices-"] || ![name hasSuffix:@".csstore"]) continue;
            NSString *candidate = [caches stringByAppendingPathComponent:name];
            struct stat st;
            if (wq_stat(candidate, &st))
                [seenNames addObject:[NSString stringWithFormat:@"%@ (%.1f MB, modified %ld)", name, st.st_size / 1048576.0,
                                      (long)st.st_mtimespec.tv_sec]];
            wq_ls_consider_candidate(candidate, &bestPath, &best, seen);
        }
        static NSString *loggedNames;
        NSString *joined = [seenNames componentsJoinedByString:@", "];
        if (seenNames.count > 1 && ![joined isEqualToString:loggedNames]) {
            loggedNames = joined;
            wq_log(@"names: stores in lsd's caches: %@; using %@", joined, bestPath.lastPathComponent ?: @"none");
        }
        if (bestPath && ![bestPath isEqualToString:cached])
            [NSUserDefaults.standardUserDefaults setObject:bestPath forKey:kWQLSStoreKey];
    }

    // Listing the daemon containers is a full id scan (minutes, and it asks
    // first); the database is found by the container scan among the newest
    // ids and remembered, so names only use the remembered location.
    if (!wq_ls_test_daemon_search) {
        if (searched) *searched = bestPath != nil;
        return bestPath;
    }
    NSArray *daemons = wq_enumerate(@"/private/var/mobile/Containers/Data/InternalDaemon", 0, nil, nil);
    if (daemons && searched) *searched = YES;
    if (daemons) {
        for (NSString *container in daemons) {
            NSString *caches = [container stringByAppendingPathComponent:@"Library/Caches"];
            NSArray *items = wq_list(caches, NULL);
            for (NSString *name in [items sortedArrayUsingSelector:@selector(compare:)]) {
                if (![name hasPrefix:@"com.apple.LaunchServices-"] || ![name hasSuffix:@".csstore"]) continue;
                wq_ls_consider_candidate([caches stringByAppendingPathComponent:name], &bestPath, &best, seen);
            }
        }
    }

    // Keep a valid cached path usable if enumeration is temporarily unavailable.
    if (!bestPath && cachedValid) {
        bestPath = cached;
    }
    return bestPath;
}

// Record layouts by release. Offsets are from the record body (after the
// 8-byte header). iOS 26 records are 0x14 bytes shorter, with the container
// path and the fields after it 4 bytes earlier than on 27.0.
typedef struct {
    const char *label;
    uint32_t bundleSize, bundleID, container, name, displayName, bundlePath;
    uint32_t pluginSize, pluginBundleID, pluginContainer;
} WQLSLayout;
static const WQLSLayout kWQLSLayouts[] = {
    { "27.0", 0x250, 0x0c, 0x68, 0x6c, 0x74, 0x00, 0x118, 0x00, 0x54 },
    { "26",   0x23c, 0x0c, 0x64, 0x68, 0x70, 0x00, 0x104, 0x00, 0x50 },
    // iOS 26.5 (from a device's layout hint, issue #37): same record sizes,
    // container fields 4 bytes earlier than on 26.7. Whether the bundle id
    // moved too isn't known, so both positions are tried.
    { "26.5",  0x23c, 0x0c, 0x60, 0x64, 0x6c, 0x00, 0x104, 0x00, 0x4c },
    { "26.5b", 0x23c, 0x08, 0x60, 0x64, 0x6c, 0x00, 0x104, 0x00, 0x4c },
    // iOS 27.2 (from a device's layout hint): container fields 4 bytes later
    // than on 27.0. Whether the bundle id moved too isn't known yet, so both
    // positions are tried; the one that maps the most containers wins.
    { "27.2", 0x25c, 0x0c, 0x6c, 0x70, 0x78, 0x00, 0x120, 0x00, 0x58 },
    { "27.2b", 0x25c, 0x10, 0x6c, 0x70, 0x78, 0x00, 0x120, 0x04, 0x58 },
    { "27.2c", 0x25c, 0x0c, 0x6c, 0x70, 0x78, 0x00, 0x120, 0x04, 0x58 },
    { "27.2d", 0x25c, 0x10, 0x6c, 0x70, 0x78, 0x00, 0x120, 0x00, 0x58 },
    // iOS 27.3 beta (issue #50): app records as on 27.2, plugin records
    // changed. Confirmed on a device (24C5037i): "27.3d", 0xf0-byte plugin
    // records with the bundle id at +0x04 and the container at +0x6c, mapped
    // 1491 of 1493 container paths. The other three candidates from the
    // layout hint stay as fallbacks for other 27.3 builds.
    { "27.3",  0x25c, 0x0c, 0x6c, 0x70, 0x78, 0x00, 0x134, 0x00, 0x58 },
    { "27.3b", 0x25c, 0x0c, 0x6c, 0x70, 0x78, 0x00, 0x134, 0x04, 0x58 },
    { "27.3c", 0x25c, 0x0c, 0x6c, 0x70, 0x78, 0x00, 0x0f0, 0x00, 0x6c },
    { "27.3d", 0x25c, 0x0c, 0x6c, 0x70, 0x78, 0x00, 0x0f0, 0x04, 0x6c },
};
static const size_t kWQLSLayoutCount = sizeof(kWQLSLayouts) / sizeof(kWQLSLayouts[0]);
static const size_t kWQLSMaxRecordSize = 0x25c;

static uint32_t wq_rd32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }

static NSString *wq_cs_string(const uint8_t *b, size_t n, size_t o)
{
    if (o > n || n - o < 8) return nil;
    uint32_t len = wq_rd32(b + o + 4);
    // Strings are padded with zero bytes to a multiple of 4. One whose length
    // is already a multiple of 4 has no terminator (container paths are 84 or
    // 88 bytes), so only shorter ones must end in a zero byte. A string must
    // still end before the buffer does.
    if (len == 0 || len >= 0x800 || len >= n - o - 8 || (len % 4 && b[o + 8 + len] != 0)) return nil;
    if (memchr(b + o + 8, 0, len)) return nil;
    NSString *s = [[NSString alloc] initWithBytes:b + o + 8 length:len encoding:NSUTF8StringEncoding];
    return s;
}

static BOOL wq_looks_like_bundle_id(NSString *s)
{
    static NSCharacterSet *bad;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bad = [[NSCharacterSet characterSetWithCharactersInString:
                @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet];
    });
    return s.length > 2 && [s containsString:@"."] && ![s hasPrefix:@"."]
        && [s rangeOfCharacterFromSet:bad].location == NSNotFound;
}

// Unicode format characters in app names. Controls that reorder text (bidi
// embeddings, overrides, isolates) could disguise a name, so inside a name
// they are replaced visibly; wrapped around the whole name they are harmless
// and dropped. Invisible marks (LRM/RLM, zero-width space, BOM, soft hyphen
// ...) are dropped: WhatsApp's name starts with U+200E. Zero-width joiners
// stay, Indic and Persian text and emoji need them.
static BOOL wq_is_name_reordering_scalar(uint32_t c)
{
    return (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069);
}

static BOOL wq_is_name_invisible_scalar(uint32_t c)
{
    return c == 0x00ad || (c >= 0x0600 && c <= 0x0605) || c == 0x061c || c == 0x06dd ||
        c == 0x070f || (c >= 0x0890 && c <= 0x0891) || c == 0x08e2 || c == 0x180e ||
        c == 0x200b || c == 0x200e || c == 0x200f || (c >= 0x2060 && c <= 0x2064) ||
        (c >= 0x206a && c <= 0x206f) || c == 0xfeff;
}

static NSString *wq_safe_name(NSString *value)
{
    if (!value.length) return nil;
    // Scalars first, so leading and trailing reordering controls can be found.
    NSMutableArray<NSNumber *> *scalars = [NSMutableArray arrayWithCapacity:value.length];
    for (NSUInteger i = 0; i < value.length;) {
        uint32_t scalar = [value characterAtIndex:i++];
        if (scalar >= 0xd800 && scalar <= 0xdbff) {
            if (i >= value.length) return nil;
            unichar low = [value characterAtIndex:i++];
            if (low < 0xdc00 || low > 0xdfff) return nil;
            scalar = 0x10000u + ((scalar - 0xd800u) << 10) + (low - 0xdc00u);
        } else if (scalar >= 0xdc00 && scalar <= 0xdfff) {
            return nil;
        }
        if (wq_is_name_invisible_scalar(scalar)) continue;
        [scalars addObject:@(scalar)];
    }
    NSUInteger first = 0, end = scalars.count;
    while (first < end && wq_is_name_reordering_scalar(scalars[first].unsignedIntValue)) first++;
    while (end > first && wq_is_name_reordering_scalar(scalars[end - 1].unsignedIntValue)) end--;

    NSMutableString *safe = [NSMutableString stringWithCapacity:value.length];
    for (NSUInteger i = first; i < end; i++) {
        uint32_t scalar = scalars[i].unsignedIntValue;
        if (wq_is_name_reordering_scalar(scalar) || scalar == 0x2028 || scalar == 0x2029) {
            [safe appendString:@"\uFFFD"];
        } else if (scalar <= 0xffff) {
            [safe appendFormat:@"%C", (unichar)scalar];
        } else {
            scalar -= 0x10000u;
            [safe appendFormat:@"%C%C", (unichar)(0xd800u + (scalar >> 10)),
             (unichar)(0xdc00u + (scalar & 0x3ffu))];
        }
    }

    NSString *normalized = [safe precomposedStringWithCanonicalMapping];
    normalized = [normalized stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!normalized.length || [normalized hasPrefix:@"/"] || [normalized containsString:@".app/"]) return nil;
    // Real control characters only (C0, DEL, C1): controlCharacterSet also
    // holds format characters, which would refuse names with a zero-width joiner.
    static NSCharacterSet *controls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableCharacterSet *set = [NSMutableCharacterSet characterSetWithRange:NSMakeRange(0, 0x20)];
        [set addCharactersInRange:NSMakeRange(0x7f, 0x21)];
        controls = [set copy];
    });
    if ([normalized rangeOfCharacterFromSet:controls].location != NSNotFound) return nil;
    return normalized;
}

// Data container path -> bundle id. Apps: the Bundle record's +0x68 field;
// extensions: 0x118-byte plugin records with the bundle id at +0x00 and the
// path at +0x54. On iOS 27.2 the containers' identifier attribute can't be
// read, so this is how their folders get a bundle id (and a name).
static BOOL wq_is_data_container_path(NSString *path)
{
    static NSArray<NSString *> *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefixes = @[@"/private/var/mobile/Containers/Data/Application/",
                     @"/private/var/mobile/Containers/Data/PluginKitPlugin/"];
    });
    for (NSString *prefix in prefixes) {
        if (![path hasPrefix:prefix] || path.length != prefix.length + 36) continue;
        return [[NSUUID alloc] initWithUUIDString:[path substringFromIndex:prefix.length]] != nil;
    }
    return NO;
}

// Diagnostics: how many container paths the store holds, and which record
// sizes and offsets refer to them. Only sizes and offsets are logged (no
// names), so a Log from a release with a new layout shows where it moved.
static int wq_u32_cmp(const void *a, const void *b)
{
    uint32_t x = *(const uint32_t *)a, y = *(const uint32_t *)b;
    return x < y ? -1 : x > y;
}

// String refs of the data container paths stored in the database, sorted;
// independent of the record layout.
static NSMutableData *wq_ls_container_path_refs(const uint8_t *b, size_t n)
{
    NSMutableData *refData = [NSMutableData new];
    static const char needle[] = "/var/mobile/Containers/Data/";
    const size_t needleLen = sizeof(needle) - 1;
    const uint8_t *cursor = b, *end = b + n;
    while (cursor < end) {
        const uint8_t *hit = memmem(cursor, (size_t)(end - cursor), needle, needleLen);
        if (!hit) break;
        cursor = hit + needleLen;
        const uint8_t *start = hit;
        if ((size_t)(hit - b) >= 8 && memcmp(hit - 8, "/private", 8) == 0) start = hit - 8;
        size_t o = (size_t)(start - b);
        if (o < 8 || o % 4) continue;
        uint32_t len = wq_rd32(start - 4);
        if (len < needleLen || len > 0x100 || len > (size_t)(end - start)) continue;
        uint32_t ref = wq_rd32(start - 8) << 2;
        if (ref) [refData appendBytes:&ref length:sizeof(ref)];
        if (refData.length / sizeof(uint32_t) >= 20000) break;
    }
    NSUInteger count = refData.length / sizeof(uint32_t);
    if (count) qsort(refData.mutableBytes, count, sizeof(uint32_t), wq_u32_cmp);
    return refData;
}

// The layout hint is diagnostics only: it must stay cheap whatever the store
// holds (a malformed one can repeat path references everywhere).
static const NSUInteger kWQLSMaxVoteMatches = 32768;       // references examined
static const NSUInteger kWQLSMaxVoteSteps = 1u << 23;      // inner-loop steps
static const NSUInteger kWQLSMaxVoteKeys = 1u << 16;      // distinct (size, offset) pairs

// Votes for (record size, offset of the container reference). *steps counts
// the inner-loop work; *cutOff says a budget ended the count early.
static NSCountedSet<NSNumber *> *wq_ls_layout_votes(const uint8_t *b, size_t n, const uint32_t *refs, NSUInteger pathCount,
                                                    NSUInteger *stepsOut, BOOL *cutOff)
{
    NSCountedSet<NSNumber *> *votes = [NSCountedSet new];
    NSUInteger matches = 0, steps = 0;
    *cutOff = NO;
    for (size_t q = 0; q + 4 <= n && !*cutOff; q += 4) {
        uint32_t v = wq_rd32(b + q);
        if (!v || (v & 3) || !bsearch(&v, refs, pathCount, sizeof(uint32_t), wq_u32_cmp)) continue;
        if (++matches > kWQLSMaxVoteMatches) { *cutOff = YES; break; }
        for (size_t k = 0; k < 0x400 && q >= 8 + k; k += 4) {
            if (++steps > kWQLSMaxVoteSteps) { *cutOff = YES; break; }
            uint32_t size = wq_rd32(b + q - 8 - k + 4);
            if (size >= 0x40 && size <= 0x800 && size % 4 == 0 && k < size) {
                NSNumber *key = @((uint64_t)size << 16 | k);
                if (votes.count >= kWQLSMaxVoteKeys && ![votes containsObject:key]) continue;
                [votes addObject:key];
            }
        }
    }
    if (stepsOut) *stepsOut = steps;
    return votes;
}

#ifdef WQ_LS_TESTING
NSUInteger wq_ls_test_layout_vote_steps(NSData *data, BOOL *cutOff, NSUInteger *keys, NSUInteger *paths);
NSUInteger wq_ls_test_layout_vote_steps(NSData *data, BOOL *cutOff, NSUInteger *keys, NSUInteger *paths)
{
    NSData *refs = wq_ls_container_path_refs(data.bytes, data.length);
    NSUInteger steps = 0;
    NSCountedSet *votes = wq_ls_layout_votes(data.bytes, data.length, refs.bytes, refs.length / sizeof(uint32_t), &steps, cutOff);
    *keys = votes.count;
    *paths = refs.length / sizeof(uint32_t);
    return steps;
}
#endif

static void wq_ls_log_summary(const uint8_t *b, size_t n, NSData *refData, NSString *layout, NSUInteger bundleRecords,
                              NSUInteger pluginRecords, NSUInteger names, NSUInteger mapped)
{
    NSUInteger pathCount = refData.length / sizeof(uint32_t);
    const uint32_t *refs = refData.bytes;
    wq_log(@"names: store %.1f MB, layout %@: %lu bundle and %lu plugin records, %lu names, %lu of %lu container paths mapped",
           n / 1048576.0, layout, (unsigned long)bundleRecords, (unsigned long)pluginRecords, (unsigned long)names,
           (unsigned long)mapped, (unsigned long)pathCount);
    if (!pathCount || mapped * 2 >= pathCount) return;

    BOOL cutOff = NO;
    NSCountedSet<NSNumber *> *votes = wq_ls_layout_votes(b, n, refs, pathCount, NULL, &cutOff);
    if (cutOff) wq_log(@"names: layout hint stopped at its work limit");
    NSArray *top = [votes.allObjects sortedArrayUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) {
        NSUInteger cx = [votes countForObject:x], cy = [votes countForObject:y];
        return cx > cy ? NSOrderedAscending : cx < cy ? NSOrderedDescending : [x compare:y];
    }];
    NSMutableArray *parts = [NSMutableArray new], *large = [NSMutableArray new];
    for (NSNumber *key in top) {
        uint64_t value = key.unsignedLongLongValue;
        NSString *text = [NSString stringWithFormat:@"0x%llx@0x%llx x%lu", value >> 16, value & 0xffff,
                          (unsigned long)[votes countForObject:key]];
        if (parts.count < 8) [parts addObject:text];
        // App and plug-in records are large; small index records can outvote them.
        if ((value >> 16) >= 0xe0 && large.count < 8) [large addObject:text];
        if (parts.count >= 8 && large.count >= 8) break;
    }
    wq_log(@"names: layout hint (record size@container offset): %@", [parts componentsJoinedByString:@", "]);
    if (large.count) wq_log(@"names: layout hint, records of 0xe0 bytes or more: %@", [large componentsJoinedByString:@", "]);
}

static NSDictionary<NSString *, NSString *> *wq_builtin_names(void);
static NSString *wq_safe_name(NSString *value);

#ifdef WQ_LS_TESTING
BOOL wq_ls_test_known_layouts_off;
#endif

// Unknown layouts (a new iOS release): the records that point to container
// paths are found from the layout votes; for each candidate record type the
// offset holding a bundle id is searched (scored by distinct ids, so a type
// field that repeats one value never wins). It must map at least half of the
// container paths to be trusted at all. Names: the offset whose string equals
// the built-in names of Apple's apps, in every candidate type.
//
// Names and the list of container paths are used; the container -> bundle id
// map is not: a folder's identity decides where backups go and what a
// restore may replace, and a worked-out layout matched one container wrongly
// in a thousand in testing. *containersOut maps every listed path to NSNull
// (no identity); identities keep coming from the container's own identifier
// (or a known layout). The worked-out offsets are remembered per iOS build.
// `description` is for the Log.
static BOOL wq_ls_auto_layout_compute(const uint8_t *b, size_t n, size_t heap, NSData *pathRefs,
                                      NSDictionary **containersOut, NSDictionary **displayOut, NSString **description);

static BOOL wq_ls_auto_layout(const uint8_t *b, size_t n, size_t heap, NSData *pathRefs,
                              NSDictionary **containersOut, NSDictionary **displayOut, NSString **description)
{
    // The name loader and the container scan parse the same store: the work
    // (a few seconds on a phone) is done once per store contents.
    static NSData *cachedKey;
    static NSDictionary *cachedResult;
    NSMutableData *key = [NSMutableData dataWithBytes:&n length:sizeof(n)];
    [key appendBytes:b length:MIN(n, (size_t)65536)];
    if (n > 65536) [key appendBytes:b + n - 65536 length:65536];
    @synchronized (NSObject.class) {
        if ([cachedKey isEqualToData:key]) {
            if (![cachedResult[@"ok"] boolValue]) return NO;
            if (containersOut) *containersOut = cachedResult[@"containers"];
            if (displayOut) *displayOut = cachedResult[@"display"];
            if (description) *description = cachedResult[@"description"];
            return YES;
        }
    }
    NSDictionary *computedContainers = nil, *computedDisplay = nil;
    NSString *computedDescription = nil;
    BOOL ok = wq_ls_auto_layout_compute(b, n, heap, pathRefs, &computedContainers, &computedDisplay, &computedDescription);
    @synchronized (NSObject.class) {
        cachedKey = key;
        cachedResult = ok ? @{ @"ok": @YES, @"containers": computedContainers, @"display": computedDisplay,
                               @"description": computedDescription } : @{ @"ok": @NO };
    }
    if (ok) {
        if (containersOut) *containersOut = computedContainers;
        if (displayOut) *displayOut = computedDisplay;
        if (description) *description = computedDescription;
    }
    return ok;
}

// Records of the given types ((size << 16) | container offset) that point at
// a container path, collected in one pass over the store, and the strings
// those records refer to (general table and path table, as in the normal
// parser; an id with two different paths is unusable).
static NSArray<NSData *> *wq_ls_auto_collect(const uint8_t *b, size_t n, size_t heap, const uint32_t *refs, NSUInteger pathCount,
                                            NSArray<NSNumber *> *keys, NSMutableDictionary<NSNumber *, NSString *> *strings,
                                            NSMutableDictionary<NSNumber *, id> *paths)
{
    enum { kMaxTypes = 16 };
    NSUInteger count = MIN(keys.count, (NSUInteger)kMaxTypes);
    uint32_t sizes[kMaxTypes], coffs[kMaxTypes];
    NSMutableArray<NSMutableData *> *records = [NSMutableArray new];
    for (NSUInteger c = 0; c < count; c++) {
        sizes[c] = (uint32_t)(keys[c].unsignedLongLongValue >> 16);
        coffs[c] = (uint32_t)(keys[c].unsignedLongLongValue & 0xffff);
        [records addObject:[NSMutableData new]];
    }
    const uint32_t kIDs = kWQLSMaxStringID;
    uint8_t *need = calloc(kIDs / 8, 1);
    if (!need) return @[];
    NSUInteger total = 0;
    for (size_t o = 0; o + 8 <= n && total < 200000; o += 4) {
        uint32_t size = wq_rd32(b + o + 4);
        for (NSUInteger c = 0; c < count; c++) {
            if (size != sizes[c] || o + 8 + size > n || coffs[c] + 4 > size) continue;
            uint32_t ref = wq_rd32(b + o + 8 + coffs[c]);
            if (!ref || (ref & 3) || !bsearch(&ref, refs, pathCount, sizeof(uint32_t), wq_u32_cmp)) continue;
            uint32_t at = (uint32_t)(o + 8);
            [records[c] appendBytes:&at length:sizeof(at)];
            total++;
            for (uint32_t k = 0; k + 4 <= size; k += 4) {
                uint32_t r = wq_rd32(b + o + 8 + k);
                if (r && !(r & 3) && (r >> 2) < kIDs) need[(r >> 2) / 8] |= 1 << ((r >> 2) % 8);
            }
        }
    }
    for (size_t o = 0; o + 8 <= n && strings.count < kWQLSMaxDecodedStrings; o += 4) {
        uint32_t sid = wq_rd32(b + o);
        if (!sid || sid >= kIDs || !(need[sid / 8] & (1 << (sid % 8)))) continue;
        uint32_t len = wq_rd32(b + o + 4);
        if (!len || len >= 0x800) continue;
        BOOL pathShaped = o + 8 < n && b[o + 8] == '/';
        if (!pathShaped && strings[@(sid)] && o < heap) continue;
        NSString *str = wq_cs_string(b, n, o);
        if (!str) continue;
        if (pathShaped) {
            if ([str containsString:@"/mobile/Containers/Data/"]) {
                id previous = paths[@(sid)];
                if (!previous) paths[@(sid)] = str;
                else if (![previous isEqual:str]) paths[@(sid)] = NSNull.null;
            }
            continue;
        }
        if (!strings[@(sid)] || o >= heap) strings[@(sid)] = str;
    }
    free(need);
    return records;
}

static NSString *wq_ls_os_build(void)
{
    char build[64] = {0};
    size_t len = sizeof(build);
    return sysctlbyname("kern.osversion", build, &len, NULL, 0) == 0 ? @(build) : @"";
}

// The worked-out layout of this iOS build, so later launches skip the search.
static NSString *const kWQLSAutoLayoutKey = @"WQLaunchServicesWorkedOutLayout";

static BOOL wq_ls_auto_layout_compute(const uint8_t *b, size_t n, size_t heap, NSData *pathRefs,
                                      NSDictionary **containersOut, NSDictionary **displayOut, NSString **description)
{
    const uint32_t *refs = pathRefs.bytes;
    NSUInteger pathCount = pathRefs.length / sizeof(uint32_t);
    if (pathCount < 20) return NO;
    NSUInteger minVotes = MAX((NSUInteger)10, pathCount / 50);
    NSString *osBuild = wq_ls_os_build();

    // A layout worked out before on this iOS build: types with their offsets.
    NSDictionary *remembered = [NSUserDefaults.standardUserDefaults dictionaryForKey:kWQLSAutoLayoutKey];
    NSArray<NSDictionary *> *types = nil;
    BOOL fromMemory = NO;
    if ([remembered[@"build"] isEqual:osBuild] && [remembered[@"types"] isKindOfClass:NSArray.class]) {
        types = remembered[@"types"];
        fromMemory = types.count > 0;
    }

    NSMutableDictionary<NSNumber *, NSString *> *strings = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, id> *paths = [NSMutableDictionary new];
    NSArray<NSData *> *candidateRecords = nil;
    NSArray<NSNumber *> *ranked = nil;
    if (fromMemory) {
        NSMutableArray *keys = [NSMutableArray new];
        for (NSDictionary *t in types) [keys addObject:@([t[@"size"] unsignedLongLongValue] << 16 | [t[@"container"] unsignedLongLongValue])];
        ranked = keys;
    } else {
        BOOL cutOff = NO;
        NSCountedSet<NSNumber *> *votes = wq_ls_layout_votes(b, n, refs, pathCount, NULL, &cutOff);
        ranked = [[votes.allObjects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:
            ^BOOL(NSNumber *key, NSDictionary *__unused bindings) { return [votes countForObject:key] >= minVotes; }]]
            sortedArrayUsingComparator:^NSComparisonResult(NSNumber *x, NSNumber *y) {
                NSUInteger cx = [votes countForObject:x], cy = [votes countForObject:y];
                return cx > cy ? NSOrderedAscending : cx < cy ? NSOrderedDescending : [x compare:y];
            }];
        if (ranked.count > 10) ranked = [ranked subarrayWithRange:NSMakeRange(0, 10)];
    }
    if (!ranked.count) return NO;
    candidateRecords = wq_ls_auto_collect(b, n, heap, refs, pathCount, ranked, strings, paths);
    if (candidateRecords.count != ranked.count) return NO;
    NSString *(^pathFor)(uint32_t) = ^NSString *(uint32_t ref) {
        id path = paths[@(ref >> 2)];
        if (![path isKindOfClass:NSString.class]) return nil;
        NSString *clean = [path hasSuffix:@"/"] ? [path substringToIndex:[path length] - 1] : path;
        if ([clean hasPrefix:@"/var/"]) clean = [@"/private" stringByAppendingString:clean];
        return wq_is_data_container_path(clean) ? clean : nil;
    };
    // Container -> bundle id for one record type and bundle id offset.
    NSMutableDictionary *(^mapFor)(NSUInteger, uint32_t, uint32_t) = ^NSMutableDictionary *(NSUInteger c, uint32_t coff, uint32_t boff) {
        const uint32_t *at = candidateRecords[c].bytes;
        NSUInteger count = candidateRecords[c].length / sizeof(uint32_t);
        NSMutableDictionary<NSString *, id> *map = [NSMutableDictionary new];
        for (NSUInteger i = 0; i < count; i++) {
            uint32_t bref = wq_rd32(b + at[i] + boff), cref = wq_rd32(b + at[i] + coff);
            if (!bref || (bref & 3)) continue;
            NSString *bid = strings[@(bref >> 2)], *path = pathFor(cref);
            if (!path || !wq_looks_like_bundle_id(bid)) continue;
            id known = map[path];
            if (!known) map[path] = bid;
            else if (![known isEqual:bid]) map[path] = NSNull.null;
        }
        for (NSString *path in map.allKeys) if (map[path] == NSNull.null) [map removeObjectForKey:path];
        return map;
    };

    // Per type: the bundle id offset (searched, or remembered).
    NSMutableArray<NSDictionary *> *results = [NSMutableArray new];
    for (NSUInteger c = 0; c < ranked.count; c++) {
        uint32_t size = (uint32_t)(ranked[c].unsignedLongLongValue >> 16), coff = (uint32_t)(ranked[c].unsignedLongLongValue & 0xffff);
        NSDictionary *best = nil;
        if (fromMemory) {
            uint32_t boff = [types[c][@"bundle"] unsignedIntValue];
            if (boff + 4 > size) continue;
            NSMutableDictionary *map = mapFor(c, coff, boff);
            best = @{ @"map": map, @"distinct": @([NSSet setWithArray:map.allValues].count), @"size": @(size), @"container": @(coff),
                      @"bundle": @(boff), @"index": @(c), @"name": types[c][@"name"] ?: @(-1), @"used": types[c][@"used"] ?: @NO };
        } else {
            for (uint32_t boff = 0; boff + 4 <= size; boff += 4) {
                if (boff == coff) continue;
                NSMutableDictionary *map = mapFor(c, coff, boff);
                // A real bundle id field holds a different id for nearly every
                // container; a type or class field ("public.mime-type") repeats.
                // Scored by distinct ids, and a field that mostly repeats is out.
                NSUInteger distinct = [NSSet setWithArray:map.allValues].count;
                if (distinct * 10 < map.count * 9) continue;
                if (distinct > [best[@"distinct"] unsignedIntegerValue])
                    best = @{ @"map": map, @"distinct": @(distinct), @"size": @(size), @"container": @(coff), @"bundle": @(boff), @"index": @(c) };
            }
        }
        if (best && [best[@"map"] count] >= minVotes) [results addObject:best];
    }
    [results sortUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        NSUInteger cx = [x[@"map"] count], cy = [y[@"map"] count];
        return cx > cy ? NSOrderedAscending : cx < cy ? NSOrderedDescending : NSOrderedSame;
    }];
    if (!results.count) {
        if (fromMemory) [NSUserDefaults.standardUserDefaults removeObjectForKey:kWQLSAutoLayoutKey];
        return NO;
    }

    // Plausibility: the best one or two types together must map at least
    // half of the container paths without conflicts.
    NSMutableDictionary<NSString *, id> *containers = [results[0][@"map"] mutableCopy];
    NSMutableArray<NSDictionary *> *used = [NSMutableArray arrayWithObject:results[0]];
    for (NSUInteger r = 1; r < results.count && used.count < 2; r++) {
        NSDictionary *other = results[r];
        if ([other[@"size"] isEqual:results[0][@"size"]]) continue;   // the same record type
        NSUInteger added = 0, conflicts = 0;
        NSDictionary *map = other[@"map"];
        for (NSString *path in map) {
            id known = containers[path];
            if (!known) added++;
            else if (![known isEqual:map[path]]) conflicts++;
        }
        if (conflicts * 20 > map.count || added < minVotes) continue;   // disagrees, or adds nothing
        for (NSString *path in map) {
            id known = containers[path];
            if (!known) containers[path] = map[path];
            else if (![known isEqual:map[path]]) containers[path] = NSNull.null;
        }
        [used addObject:other];
    }
    for (NSString *path in containers.allKeys) if (containers[path] == NSNull.null) [containers removeObjectForKey:path];
    if (containers.count * 2 < pathCount) {
        if (fromMemory) [NSUserDefaults.standardUserDefaults removeObjectForKey:kWQLSAutoLayoutKey];
        return NO;
    }

    // Names: per type, the offset whose string is the known name of Apple's
    // apps (searched, or remembered). Fewer than three matches: no names.
    NSDictionary<NSString *, NSString *> *builtin = wq_builtin_names();
    NSMutableDictionary<NSString *, NSString *> *display = [NSMutableDictionary new];
    NSMutableArray<NSString *> *parts = [NSMutableArray new];
    NSMutableArray<NSDictionary *> *rememberTypes = [NSMutableArray new];
    for (NSDictionary *result in results) {
        NSUInteger c = [result[@"index"] unsignedIntegerValue];
        uint32_t size = [result[@"size"] unsignedIntValue], boff = [result[@"bundle"] unsignedIntValue];
        const uint32_t *at = candidateRecords[c].bytes;
        NSUInteger count = candidateRecords[c].length / sizeof(uint32_t);
        int64_t bestName = -1;
        NSUInteger bestMatches = 0;
        int64_t rememberedName = fromMemory ? [result[@"name"] longLongValue] : -1;
        for (uint32_t noff = 0; noff + 4 <= size; noff += 4) {
            if (noff == boff) continue;
            if (fromMemory && (int64_t)noff != rememberedName) continue;
            NSUInteger matches = 0;
            for (NSUInteger i = 0; i < count; i++) {
                uint32_t bref = wq_rd32(b + at[i] + boff), nref = wq_rd32(b + at[i] + noff);
                if ((bref & 3) || (nref & 3) || !nref) continue;
                NSString *known = builtin[strings[@(bref >> 2)] ?: @""];
                if (known && [strings[@(nref >> 2)] isEqualToString:known]) matches++;
            }
            if (matches > bestMatches) { bestMatches = matches; bestName = noff; }
        }
        BOOL named = bestMatches >= 3;
        if (named) {
            for (NSUInteger i = 0; i < count; i++) {
                uint32_t bref = wq_rd32(b + at[i] + boff), nref = wq_rd32(b + at[i] + (uint32_t)bestName);
                if ((bref & 3) || (nref & 3) || !nref) continue;
                NSString *bid = strings[@(bref >> 2)], *name = wq_safe_name(strings[@(nref >> 2)]);
                if (wq_looks_like_bundle_id(bid) && name && !display[bid]) display[bid] = name;
            }
        }
        BOOL isUsed = [used containsObject:result];
        if (isUsed || named) {
            [parts addObject:[NSString stringWithFormat:@"0x%x-byte records (container +0x%x, bundle id +0x%x, name %@): %lu",
                              size, [result[@"container"] unsignedIntValue], boff,
                              named ? [NSString stringWithFormat:@"+0x%llx", bestName] : @"not found",
                              (unsigned long)[result[@"map"] count]]];
            [rememberTypes addObject:@{ @"size": @(size), @"container": result[@"container"], @"bundle": @(boff),
                                        @"name": @(named ? bestName : -1), @"used": @(isUsed) }];
        }
    }
    if (!fromMemory)
        [NSUserDefaults.standardUserDefaults setObject:@{ @"build": osBuild, @"types": rememberTypes } forKey:kWQLSAutoLayoutKey];
    // The container list: every data container path these records point at,
    // with no app attached (NSNull). The paths themselves are just strings of
    // the store (the scan checks that they exist); which app a folder belongs
    // to keeps coming from the folder's own identifier.
    NSMutableDictionary<NSString *, id> *listed = [NSMutableDictionary new];
    for (id path in paths.allValues) {
        if (![path isKindOfClass:NSString.class]) continue;
        NSString *clean = [path hasSuffix:@"/"] ? [path substringToIndex:[path length] - 1] : path;
        if ([clean hasPrefix:@"/var/"]) clean = [@"/private" stringByAppendingString:clean];
        if (wq_is_data_container_path(clean)) listed[clean] = NSNull.null;
    }
    if (containersOut) *containersOut = [listed copy];
    if (displayOut) *displayOut = [display copy];
    if (description) *description = [NSString stringWithFormat:@"%@%@; %lu of %lu container paths, %lu names",
                                      fromMemory ? @"(remembered for this iOS build) " : @"",
                                      [parts componentsJoinedByString:@" + "], (unsigned long)containers.count,
                                      (unsigned long)pathCount, (unsigned long)display.count];
    return YES;
}

static BOOL wq_parse_ls_store(NSData *data, NSDictionary **displayOut,
                              NSDictionary **bundleNameOut, NSDictionary **containersOut,
                              NSDictionary **bundlePathsOut)
{
    if (bundlePathsOut) *bundlePathsOut = nil;
    if (displayOut) *displayOut = nil;
    if (bundleNameOut) *bundleNameOut = nil;
    if (containersOut) *containersOut = nil;

    const uint8_t *b = data.bytes;
    size_t n = data.length;
    if (n < kWQLSMinStoreBytes || !b || memcmp(b, "bdsl", 4) != 0) {
        wq_log(@"names: not a LaunchServices store");
        return NO;
    }
    NSRange heapRange = [data rangeOfData:[NSData dataWithBytes:"<string>" length:8]
                                  options:0 range:NSMakeRange(0, n)];
    size_t heap = heapRange.location == NSNotFound ? 0 : heapRange.location;

    // Pass 1: Bundle and plug-in records of every known layout, and which
    // string ids they need. The layout that maps the most containers wins.
    const uint32_t kIDs = kWQLSMaxStringID;
    size_t bitsetBytes = kIDs / 8;
    uint8_t *need = calloc(bitsetBytes, 1), *inHeap = calloc(bitsetBytes, 1);
    NSMutableArray<NSMutableData *> *layoutRecs = [NSMutableArray new], *layoutPlugins = [NSMutableArray new];
    for (size_t l = 0; l < kWQLSLayoutCount; l++) {
        [layoutRecs addObject:[NSMutableData new]];
        [layoutPlugins addObject:[NSMutableData new]];   // pairs: bundle id ref, container path ref
    }
    if (!need || !inHeap) {
        free(need);
        free(inHeap);
        wq_log(@"names: LaunchServices parser allocation failed");
        return NO;
    }

    BOOL tooManyRecords = NO;
    for (size_t o = 0; o + 8 + kWQLSMaxRecordSize <= n && !tooManyRecords; o += 4) {
        uint32_t size = wq_rd32(b + o + 4);
        const uint8_t *u = b + o + 8;
        for (size_t l = 0; l < kWQLSLayoutCount; l++) {
            const WQLSLayout *L = &kWQLSLayouts[l];
            if (size == L->pluginSize) {
                NSMutableData *plugins = layoutPlugins[l];
                uint32_t p[2] = { wq_rd32(u + L->pluginBundleID), wq_rd32(u + L->pluginContainer) };
                if (p[0] && !(p[0] & 3) && (p[0] >> 2) < kIDs && p[1] && !(p[1] & 3) && (p[1] >> 2) < kIDs &&
                    plugins.length / sizeof(p) < kWQLSMaxBundleRecords) {
                    [plugins appendBytes:p length:sizeof(p)];
                    for (int i = 0; i < 2; i++) need[(p[i] >> 2) / 8] |= 1 << ((p[i] >> 2) % 8);
                }
            }
            if (size != L->bundleSize) continue;
            NSMutableData *recs = layoutRecs[l];
            if (recs.length / (5 * sizeof(uint32_t)) >= kWQLSMaxBundleRecords) {
                tooManyRecords = YES;
                break;
            }
            uint32_t r[5] = { wq_rd32(u + L->bundleID), wq_rd32(u + L->name), wq_rd32(u + L->displayName), wq_rd32(u + L->container),
                              wq_rd32(u + L->bundlePath) };
            if (!r[0] || (r[0] & 3) || (r[0] >> 2) >= kIDs) continue;
            [recs appendBytes:r length:sizeof(r)];
            for (int i = 0; i < 5; i++) {
                if (r[i] && !(r[i] & 3) && (r[i] >> 2) < kIDs)
                    need[(r[i] >> 2) / 8] |= 1 << ((r[i] >> 2) % 8);
            }
        }
    }
    if (tooManyRecords) {
        free(need);
        free(inHeap);
        wq_log(@"names: LaunchServices store exceeds record limit");
        return NO;
    }

    // Pass 2: the strings, preferring copies inside the string table. On
    // iOS 26 container paths live in a second table whose ids overlap the
    // string table's, so path-shaped strings are also kept by id on their own
    // (an id with two different paths is unusable).
    NSMutableDictionary<NSNumber *, NSString *> *strings = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, id> *pathStrings = [NSMutableDictionary new];
    NSMutableDictionary<NSNumber *, id> *appPathStrings = [NSMutableDictionary new];
    NSUInteger decodedStringBytes = 0;
    BOOL tooManyStrings = NO;
    for (size_t o = 0; o <= n - 8; o += 4) {
        uint32_t sid = wq_rd32(b + o);
        if (!sid || sid >= kIDs || !(need[sid / 8] & (1 << (sid % 8)))) continue;
        BOOL here = o >= heap, had = strings[@(sid)] != nil;
        BOOL keepGeneral = !had || (here && !(inHeap[sid / 8] & (1 << (sid % 8))));
        uint32_t peekLen = o + 8 <= n ? wq_rd32(b + o + 4) : 0;
        BOOL maybePath = peekLen >= 6 && peekLen < 0x400 && o + 8 < n && b[o + 8] == '/';
        if (!keepGeneral && !maybePath) continue;
        NSString *s = wq_cs_string(b, n, o);
        if (!s) continue;
        if (maybePath) {
            NSMutableDictionary *table = [s containsString:@"/mobile/Containers/Data/"] ? pathStrings
                : ([s hasSuffix:@".app"] || [s hasSuffix:@".app/"]) ? appPathStrings : nil;
            id previous = table[@(sid)];
            if (table && !previous) table[@(sid)] = s;
            else if (table && ![previous isEqual:s]) table[@(sid)] = NSNull.null;
        }
        if (!keepGeneral) continue;
        if (!had && (strings.count >= kWQLSMaxDecodedStrings ||
                     s.length > kWQLSMaxDecodedStringBytes - decodedStringBytes)) {
            tooManyStrings = YES;
            break;
        }
        strings[@(sid)] = s;
        if (!had) decodedStringBytes += s.length;
        if (here) inHeap[sid / 8] |= 1 << (sid % 8);
    }
    free(need);
    free(inHeap);
    if (tooManyStrings) {
        wq_log(@"names: LaunchServices store exceeds string limit");
        return NO;
    }
    NSUInteger anyRecords = 0, anyPlugins = 0;
    for (size_t l = 0; l < kWQLSLayoutCount; l++) {
        anyRecords += layoutRecs[l].length / (5 * sizeof(uint32_t));
        anyPlugins += layoutPlugins[l].length / (2 * sizeof(uint32_t));
    }
    if (!anyRecords) {
        NSData *refs = wq_ls_container_path_refs(b, n);
        wq_ls_log_summary(b, n, refs, @"none", 0, anyPlugins, 0, 0);
        NSDictionary *autoContainers = nil, *autoDisplay = nil;
        NSString *autoDescription = nil;
        if (wq_ls_auto_layout(b, n, heap, refs, &autoContainers, &autoDisplay, &autoDescription)) {
            wq_log(@"names: unknown layout, worked out from the store: %@", autoDescription);
            if (displayOut) *displayOut = autoDisplay;
            if (bundleNameOut) *bundleNameOut = @{};
            if (containersOut) *containersOut = autoContainers;   // paths only, no identities: see wq_ls_auto_layout
            if (bundlePathsOut) *bundlePathsOut = @{};
            return YES;
        }
        wq_log(@"names: LaunchServices store contains no bundle records");
        return NO;
    }

    NSString *(^pathFor)(uint32_t) = ^NSString *(uint32_t ref) {
        id path = pathStrings[@(ref >> 2)];
        if (path == NSNull.null) return nil;
        return path ?: strings[@(ref >> 2)];
    };
    NSDictionary *display = nil, *bundleName = nil, *containers = nil, *bundlePaths = nil;
    size_t chosen = 0;
    for (size_t l = 0; l < kWQLSLayoutCount; l++) {
        NSMutableDictionary *layoutDisplay = [NSMutableDictionary new], *layoutBundleName = [NSMutableDictionary new];
        NSMutableDictionary *layoutBundlePaths = [NSMutableDictionary new];
        NSMutableDictionary<NSString *, id> *layoutContainers = [NSMutableDictionary new];
        // A path claimed by two different bundle ids is left out rather than guessed.
        // Plug-in records only claim extension containers and bundle records
        // only app containers, so a record type that happens to share a size
        // can't knock out the other table's paths.
        void (^claim)(NSString *, NSString *, NSString *) = ^(NSString *path, NSString *bid, NSString *kind) {
            // iOS 26 stores container paths with a trailing slash; lookups
            // use the /private/var form without one.
            if ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
            if ([path hasPrefix:@"/var/"]) path = [@"/private" stringByAppendingString:path];
            if (!wq_is_data_container_path(path) || !wq_looks_like_bundle_id(bid) || ![path containsString:kind]) return;
            id known = layoutContainers[path];
            if (!known) layoutContainers[path] = bid;
            else if (![known isEqual:bid]) layoutContainers[path] = NSNull.null;
        };
        NSData *plugins = layoutPlugins[l], *recs = layoutRecs[l];
        const uint32_t *pr = plugins.bytes;
        for (NSUInteger i = 0; i < plugins.length / sizeof(uint32_t); i += 2)
            claim(pathFor(pr[i + 1]), strings[@(pr[i] >> 2)], @"/Data/PluginKitPlugin/");
        const uint32_t *r = recs.bytes;
        for (NSUInteger i = 0; i < recs.length / sizeof(uint32_t); i += 5) {
            NSString *bid = strings[@(r[i] >> 2)];
            if (!wq_looks_like_bundle_id(bid)) continue;
            NSString *container = (r[i + 3] && !(r[i + 3] & 3)) ? pathFor(r[i + 3]) : nil;
            if (container) claim(container, bid, @"/Data/Application/");
            id appPath = (r[i + 4] && !(r[i + 4] & 3)) ? appPathStrings[@(r[i + 4] >> 2)] : nil;
            // Names only from real app records: ones that point at the app's
            // data container or its .app bundle. Other records of the same
            // size carry an app's id too (the document types it opens), with
            // a localized type name where the app name would be: on iOS 26.5
            // UC Browser became "셸 스크립트" (shell script).
            NSString *cleanContainer = [container isKindOfClass:NSString.class] ? container : nil;
            if ([cleanContainer hasSuffix:@"/"]) cleanContainer = [cleanContainer substringToIndex:cleanContainer.length - 1];
            if ([cleanContainer hasPrefix:@"/var/"]) cleanContainer = [@"/private" stringByAppendingString:cleanContainer];
            BOOL appRecord = (cleanContainer && wq_is_data_container_path(cleanContainer) &&
                              [cleanContainer containsString:@"/Data/Application/"]) ||
                             ([appPath isKindOfClass:NSString.class] &&
                              [[[appPath hasSuffix:@"/"] ? [appPath substringToIndex:[appPath length] - 1] : appPath pathExtension] isEqualToString:@"app"]);
            NSString *nm = (r[i + 1] & 3) || !appRecord ? nil : strings[@(r[i + 1] >> 2)];
            NSString *dn = (r[i + 2] & 3) || !appRecord ? nil : strings[@(r[i + 2] >> 2)];
            NSString *safeDisplay = wq_safe_name(dn);
            NSString *safeBundleName = wq_safe_name(nm);
            if (safeDisplay && !layoutDisplay[bid]) layoutDisplay[bid] = safeDisplay;
            if (safeBundleName && !layoutBundleName[bid]) layoutBundleName[bid] = safeBundleName;
            if ([appPath isKindOfClass:NSString.class] && !layoutBundlePaths[bid]) {
                NSString *clean = [appPath hasSuffix:@"/"] ? [appPath substringToIndex:[appPath length] - 1] : appPath;
                if ([clean hasPrefix:@"/var/"]) clean = [@"/private" stringByAppendingString:clean];
                layoutBundlePaths[bid] = clean;
            }
        }
        for (NSString *path in layoutContainers.allKeys)
            if (layoutContainers[path] == NSNull.null) [layoutContainers removeObjectForKey:path];
        if (!containers || layoutContainers.count > containers.count ||
            (layoutContainers.count == containers.count && layoutDisplay.count > display.count)) {
            display = layoutDisplay;
            bundleName = layoutBundleName;
            bundlePaths = layoutBundlePaths;
            containers = layoutContainers;
            chosen = l;
        }
    }
    // A few Apple apps' names, to check the name fields of a new layout.
    NSMutableArray *samples = [NSMutableArray new];
    for (NSString *bid in @[@"com.apple.mobilesafari", @"com.apple.Preferences", @"com.apple.camera", @"com.apple.mobilenotes"]) {
        NSString *name = display[bid] ?: bundleName[bid];
        if (name) [samples addObject:[NSString stringWithFormat:@"%@ = %@", bid, name]];
    }
    // The container scan and the name loader each parse the same store; log
    // its summary once per distinct result, not once per parse.
    static NSString *lastSummary;
    NSString *summary = [NSString stringWithFormat:@"%zu %zu %lu %lu", n, chosen, (unsigned long)display.count,
                         (unsigned long)containers.count];
    BOOL newSummary;
    @synchronized (NSObject.class) {
        newSummary = ![summary isEqualToString:lastSummary];
        if (newSummary) lastSummary = summary;
    }
    if (newSummary && samples.count) wq_log(@"names: sample: %@", [samples componentsJoinedByString:@", "]);
    NSData *pathRefs = wq_ls_container_path_refs(b, n);
    if (newSummary) wq_ls_log_summary(b, n, pathRefs, @(kWQLSLayouts[chosen].label), layoutRecs[chosen].length / (5 * sizeof(uint32_t)),
                      layoutPlugins[chosen].length / (2 * sizeof(uint32_t)), display.count, containers.count);
    // A layout that maps only a small part of the container paths in the store
    // is the wrong one (its names are wrong too): don't use the store at all,
    // so the app list falls back to the scan instead of showing a few apps.
    NSUInteger storePaths = pathRefs.length / sizeof(uint32_t);
    BOOL knownFails = storePaths >= 20 && containers.count * 2 < storePaths;
#ifdef WQ_LS_TESTING
    if (wq_ls_test_known_layouts_off) knownFails = YES;
#endif
    if (knownFails) {
        // Not a known layout: try to work it out from the store itself.
        NSDictionary *autoContainers = nil, *autoDisplay = nil;
        NSString *autoDescription = nil;
        if (wq_ls_auto_layout(b, n, heap, pathRefs, &autoContainers, &autoDisplay, &autoDescription)) {
            if (newSummary) wq_log(@"names: unknown layout, worked out from the store: %@", autoDescription);
            if (displayOut) *displayOut = autoDisplay;
            if (bundleNameOut) *bundleNameOut = @{};
            if (containersOut) *containersOut = autoContainers;   // paths only, no identities: see wq_ls_auto_layout
            if (bundlePathsOut) *bundlePathsOut = @{};
            return YES;
        }
        if (newSummary)
            wq_log(@"names: layout %s maps only %lu of %lu container paths; this iOS version's database layout isn't known, so it isn't used",
                   kWQLSLayouts[chosen].label, (unsigned long)containers.count, (unsigned long)storePaths);
        return NO;
    }
    if (bundlePathsOut) *bundlePathsOut = [bundlePaths copy];
    if (displayOut) *displayOut = [display copy];
    if (bundleNameOut) *bundleNameOut = [bundleName copy];
    if (containersOut) *containersOut = [containers copy];
    return YES;
}

static NSDictionary *gLSDisplay;
static NSDictionary *gLSBundleName;
static NSDictionary *gLSContainers;
static NSDictionary *gLSBundlePaths;
static NSArray<NSString *> *gLSAllPaths;   // containers and app groups, for the container scan
static NSDictionary<NSString *, NSString *> *gLSGroupIDs;   // group folder -> group id
static NSString *gLSStorePath;
static NSDictionary *gLSStoreSignature;
static BOOL gLSLoaded;
static NSUInteger gLSFailureCount;
static NSTimeInterval gLSNextRetryAt;

static void wq_ls_clear_snapshot_if_changed(BOOL changed)
{
    if (!changed) return;
    gLSDisplay = nil;
    gLSBundleName = nil;
    gLSContainers = nil;
    gLSBundlePaths = nil;
    gLSAllPaths = nil;
    gLSGroupIDs = nil;
    gLSStorePath = nil;
    gLSStoreSignature = nil;
    gLSLoaded = NO;
}

static void wq_ls_note_failure(NSTimeInterval now, NSString *reason)
{
    gLSFailureCount = MIN(gLSFailureCount + 1, (NSUInteger)6);
    NSUInteger shift = gLSFailureCount > 1 ? gLSFailureCount - 1 : 0;
    NSTimeInterval delay = (NSTimeInterval)(1u << MIN(shift, (NSUInteger)5));
    gLSNextRetryAt = now + delay;
    if (reason) wq_log(@"names: %@; retrying in %.0f s", reason, delay);
}

static NSString *const kWQGroupRoot = @"/private/var/mobile/Containers/Shared/AppGroup/";

static uint64_t wq_be(const uint8_t *p, NSUInteger n)
{
    uint64_t v = 0;
    for (NSUInteger i = 0; i < n; i++) v = v << 8 | p[i];
    return v;
}

// Length of the binary plist starting at `start` (its trailer must end
// exactly where the offset table says), or 0.
static NSUInteger wq_bplist_length(const uint8_t *start, const uint8_t *end, NSUInteger minimum, NSUInteger limit)
{
    NSUInteger available = (NSUInteger)(end - start);
    NSUInteger max = MIN(available, limit);
    for (NSUInteger length = MAX(minimum, (NSUInteger)40); length <= max; length++) {
        const uint8_t *t = start + length - 32;
        if (t[0] | t[1] | t[2] | t[3] | t[4]) continue;
        uint8_t offsetSize = t[6], refSize = t[7];
        if (offsetSize < 1 || offsetSize > 8 || refSize < 1 || refSize > 8) continue;
        uint64_t objects = wq_be(t + 8, 8), top = wq_be(t + 16, 8), table = wq_be(t + 24, 8);
        if (objects == 0 || objects > 100000 || top >= objects || table < 8) continue;
        if (table + objects * offsetSize + 32 != length) continue;
        return length;
    }
    return 0;
}

static NSString *wq_group_key(NSString *path)
{
    if (![path isKindOfClass:NSString.class]) return nil;
    NSString *p = path;
    if ([p hasPrefix:@"/var/"]) p = [@"/private" stringByAppendingString:p];
    while ([p hasSuffix:@"/"]) p = [p substringToIndex:p.length - 1];
    if (![p hasPrefix:kWQGroupRoot]) return nil;
    NSString *uuid = [p substringFromIndex:kWQGroupRoot.length];
    if (uuid.length != 36 || ![[NSUUID alloc] initWithUUIDString:uuid]) return nil;
    return [kWQGroupRoot stringByAppendingString:uuid.uppercaseString];
}

static BOOL wq_group_id_plausible(NSString *ident)
{
    if (![ident isKindOfClass:NSString.class] || ident.length < 3 || ident.length > 255) return NO;
    if ([ident hasPrefix:@"."] || [ident hasSuffix:@"."] || [ident containsString:@"/"]) return NO;
    return [ident containsString:@"."];
}

// Collects {id: group path} pairs anywhere in a parsed plist.
static void wq_collect_group_pairs(id object, NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *byPath, NSUInteger depth)
{
    if (depth > 6) return;
    if ([object isKindOfClass:NSDictionary.class]) {
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *__unused stop) {
            NSString *path = wq_group_key(value);
            if (path && wq_group_id_plausible(key)) {
                NSMutableSet *ids = byPath[path] ?: (byPath[path] = [NSMutableSet new]);
                [ids addObject:key];
            } else {
                wq_collect_group_pairs(value, byPath, depth + 1);
            }
        }];
    } else if ([object isKindOfClass:NSArray.class]) {
        for (id item in (NSArray *)object) wq_collect_group_pairs(item, byPath, depth + 1);
    }
}

NSDictionary<NSString *, NSString *> *wq_ls_group_ids_from_store(NSData *data)
{
    static const char needle[] = "/mobile/Containers/Shared/AppGroup/";
    static const char magic[] = "bplist00";
    const uint8_t *bytes = data.bytes, *cursor = bytes, *end = bytes + data.length;
    NSMutableIndexSet *parsed = [NSMutableIndexSet new];
    NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *byPath = [NSMutableDictionary new];
    while (cursor < end) {
        const uint8_t *hit = memmem(cursor, (size_t)(end - cursor), needle, sizeof(needle) - 1);
        if (!hit) break;
        cursor = hit + sizeof(needle) - 1;
        // The nearest plist header before the path (within 16 KB).
        const uint8_t *from = hit - MIN((size_t)(hit - bytes), (size_t)16384), *start = NULL;
        for (const uint8_t *p = hit - (sizeof(magic) - 1); p >= from; p--) {
            if (memcmp(p, magic, sizeof(magic) - 1) == 0) { start = p; break; }
            if (p == bytes) break;
        }
        if (!start) continue;
        NSUInteger offset = (NSUInteger)(start - bytes);
        if ([parsed containsIndex:offset]) continue;
        [parsed addIndex:offset];
        // A trailer-shaped run inside the plist can end it too early: then
        // parsing fails and the next candidate length is tried.
        NSUInteger minimum = (NSUInteger)(hit - start) + sizeof(needle);   // the path lies inside
        for (int attempt = 0; attempt < 8; attempt++) {
            NSUInteger length = wq_bplist_length(start, end, minimum, 65536);
            if (!length) break;
            NSData *slice = [NSData dataWithBytesNoCopy:(void *)start length:length freeWhenDone:NO];
            id plist = [NSPropertyListSerialization propertyListWithData:slice options:0 format:NULL error:NULL];
            if (plist) { wq_collect_group_pairs(plist, byPath, 0); break; }
            minimum = length + 1;
        }
    }
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary new];
    for (NSString *path in byPath) if (byPath[path].count == 1) result[path] = byPath[path].anyObject;
    return result;
}

// Every container path the store names: the data containers its records map
// plus every other app, extension and group container path string in it.
// Records whose container the parser can't pair with a bundle id (or that two
// records claim) still name a real folder; leaving them out hid installed
// apps (iOS 26.5: UC Browser missing from Apps). Those folders get their
// label from the container itself (attributes, metadata plist).
static NSArray<NSString *> *wq_ls_all_paths(NSData *data, NSDictionary *containers)
{
    NSMutableSet<NSString *> *all = [NSMutableSet setWithArray:containers.allKeys];
    NSMutableSet<NSString *> *seen = [NSMutableSet new];   // case-insensitive: mapped keys keep the store's spelling
    for (NSString *key in containers.allKeys) [seen addObject:key.uppercaseString];
    static const char *const needles[] = {
        "/mobile/Containers/Shared/AppGroup/",
        "/mobile/Containers/Data/Application/",
        "/mobile/Containers/Data/PluginKitPlugin/",
    };
    const uint8_t *bytes = data.bytes, *end = bytes + data.length;
    for (size_t i = 0; i < sizeof(needles) / sizeof(needles[0]); i++) {
        const char *needle = needles[i];
        size_t needleLength = strlen(needle);
        NSString *prefix = [@"/private/var" stringByAppendingString:@(needle)];
        const uint8_t *cursor = bytes;
        while (cursor < end) {
            const uint8_t *hit = memmem(cursor, (size_t)(end - cursor), needle, needleLength);
            if (!hit) break;
            cursor = hit + needleLength;
            if ((size_t)(end - cursor) < 36) break;
            NSString *uuid = [[NSString alloc] initWithBytes:cursor length:36 encoding:NSASCIIStringEncoding];
            if (!uuid || ![[NSUUID alloc] initWithUUIDString:uuid]) continue;
            NSString *path = [prefix stringByAppendingString:uuid.uppercaseString];
            if ([seen containsObject:path.uppercaseString]) continue;
            [seen addObject:path.uppercaseString];
            [all addObject:path];
        }
    }
    return all.allObjects;
}

// Publishes one snapshot of a store read by wq_ls_read_stable and parsed
// completely: names, container and bundle maps, the container list, its path
// and signature, and the remembered location all change together. The
// dictionaries are immutable copies, so readers see either the previous
// snapshot or this one.
static void wq_ls_publish_locked(NSString *path, const struct stat *st, NSDictionary *display, NSDictionary *bundleName,
                                 NSDictionary *containers, NSDictionary *bundlePaths, NSArray<NSString *> *allPaths,
                                 NSDictionary<NSString *, NSString *> *groupIDs)
{
    gLSDisplay = [display copy] ?: @{};
    gLSBundleName = [bundleName copy] ?: @{};
    gLSContainers = [containers copy] ?: @{};
    gLSBundlePaths = [bundlePaths copy] ?: @{};
    gLSAllPaths = [allPaths copy] ?: @[];
    gLSGroupIDs = [groupIDs copy] ?: @{};
    wq_log(@"names: %lu group folders identified from app records", (unsigned long)gLSGroupIDs.count);
    gLSStorePath = [path copy];
    gLSStoreSignature = [wq_ls_signature(st) copy];
    gLSLoaded = YES;
    gLSFailureCount = 0;
    gLSNextRetryAt = 0;
    [NSUserDefaults.standardUserDefaults setObject:gLSStorePath forKey:kWQLSStoreKey];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kWQLSMissKey];
}

static void wq_load_ls_names_locked(void)
{
    NSTimeInterval now = NSDate.date.timeIntervalSinceReferenceDate;
    BOOL currentChanged = NO;
    if (gLSLoaded && gLSStorePath) {
        struct stat current;
        if (wq_ls_candidate_info(gLSStorePath, &current)) {
            NSDictionary *signature = wq_ls_signature(&current);
            currentChanged = !wq_ls_signature_equal(signature, gLSStoreSignature);
            if (!currentChanged) return;
        } else {
            currentChanged = YES;
        }
    } else if (!gLSLoaded && now < gLSNextRetryAt) {
        return;
    } else if (!gLSLoaded && ![NSUserDefaults.standardUserDefaults stringForKey:kWQLSStoreKey].length) {
        NSDate *missed = [NSUserDefaults.standardUserDefaults objectForKey:kWQLSMissKey];
        if ([missed isKindOfClass:NSDate.class] && now - missed.timeIntervalSinceReferenceDate < kWQLSMissRetry &&
            now >= missed.timeIntervalSinceReferenceDate) {
            gLSNextRetryAt = missed.timeIntervalSinceReferenceDate + kWQLSMissRetry;
            return;
        }
    }

    BOOL hadLocation = [NSUserDefaults.standardUserDefaults stringForKey:kWQLSStoreKey].length > 0;
    BOOL searched = NO;
    NSString *path = wq_find_ls_store(&searched);
    if (!path) {
        wq_ls_clear_snapshot_if_changed(currentChanged);
        if (!hadLocation && searched) {
            // Never found, after a complete search: wait a day (or a refresh).
            [NSUserDefaults.standardUserDefaults setObject:NSDate.date forKey:kWQLSMissKey];
            gLSNextRetryAt = now + kWQLSMissRetry;
            wq_log(@"names: LaunchServices database not found; searching again in a day or on refresh");
        } else {
            // A known database that's briefly unreadable, or a scan that failed.
            wq_ls_note_failure(now, @"LaunchServices database not found");
        }
        return;
    }
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kWQLSMissKey];

    struct stat before;
    if (!wq_ls_candidate_info(path, &before)) {
        wq_ls_clear_snapshot_if_changed(currentChanged);
        wq_ls_note_failure(now, wq_ls_error(path, @"candidate is no longer valid"));
        return;
    }
    NSDictionary *beforeSignature = wq_ls_signature(&before);
    BOOL snapshotChanged = !gLSLoaded || ![path isEqualToString:gLSStorePath] ||
        !wq_ls_signature_equal(beforeSignature, gLSStoreSignature);
    if (gLSLoaded && [path isEqualToString:gLSStorePath] &&
        wq_ls_signature_equal(beforeSignature, gLSStoreSignature)) {
        gLSFailureCount = 0;
        gLSNextRetryAt = 0;
        return;
    }

    // Not published when the store changed while it was read.
    NSString *error = nil;
    NSData *data = wq_ls_read_stable(path, &before, &error);
    if (!data) {
        wq_ls_clear_snapshot_if_changed(snapshotChanged);
        wq_ls_note_failure(now, wq_ls_error(path, error));
        return;
    }

    NSDictionary *display = nil, *bundleName = nil, *containers = nil, *bundlePaths = nil;
    if (!wq_parse_ls_store(data, &display, &bundleName, &containers, &bundlePaths)) {
        wq_ls_clear_snapshot_if_changed(snapshotChanged);
        wq_ls_note_failure(now, wq_ls_error(path, @"store rejected by bounded parser"));
        return;
    }
    wq_ls_publish_locked(path, &before, display, bundleName, containers, bundlePaths, wq_ls_all_paths(data, containers),
                         wq_ls_group_ids_from_store(data));
}

// Apple's own apps and services: LaunchServices refuses this app on 27.x
// (OSStatus -54) and /Applications is not listable, so names come from here.
static NSDictionary<NSString *, NSString *> *wq_builtin_names(void)
{
    static NSDictionary *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @{
            @"com.apple.AppStore": @"App Store", @"com.apple.mobilesafari": @"Safari", @"com.apple.weather": @"Weather",
            @"com.apple.news": @"News", @"com.apple.stocks": @"Stocks", @"com.apple.mobilemail": @"Mail",
            @"com.apple.MobileSMS": @"Messages", @"com.apple.mobilephone": @"Phone", @"com.apple.mobileslideshow": @"Photos",
            @"com.apple.camera": @"Camera", @"com.apple.mobilecal": @"Calendar", @"com.apple.mobilenotes": @"Notes",
            @"com.apple.reminders": @"Reminders", @"com.apple.Maps": @"Maps", @"com.apple.Music": @"Music",
            @"com.apple.tv": @"TV", @"com.apple.podcasts": @"Podcasts", @"com.apple.iBooks": @"Books",
            @"com.apple.Health": @"Health", @"com.apple.Passbook": @"Wallet", @"com.apple.Preferences": @"Settings",
            @"com.apple.mobiletimer": @"Clock", @"com.apple.calculator": @"Calculator", @"com.apple.compass": @"Compass",
            @"com.apple.VoiceMemos": @"Voice Memos", @"com.apple.facetime": @"FaceTime", @"com.apple.MobileAddressBook": @"Contacts",
            @"com.apple.DocumentsApp": @"Files", @"com.apple.findmy": @"Find My", @"com.apple.Home": @"Home",
            @"com.apple.shortcuts": @"Shortcuts", @"com.apple.Translate": @"Translate", @"com.apple.Fitness": @"Fitness",
            @"com.apple.Bridge": @"Watch", @"com.apple.freeform": @"Freeform", @"com.apple.journal": @"Journal",
            @"com.apple.Passwords": @"Passwords", @"com.apple.measure": @"Measure", @"com.apple.Magnifier": @"Magnifier",
            @"com.apple.tips": @"Tips", @"com.apple.siri": @"Siri", @"com.apple.games": @"Games", @"com.apple.gamecenter": @"Game Center",
            @"com.apple.Image-Playground": @"Image Playground", @"com.apple.Photos": @"Photos", @"com.apple.Keynote": @"Keynote",
            @"com.apple.Pages": @"Pages", @"com.apple.Numbers": @"Numbers", @"com.apple.mobileme.fmip1": @"Find iPhone",
            @"com.apple.store.Jolly": @"Apple Store", @"com.apple.supportapp": @"Apple Support", @"com.apple.Diagnostics": @"Diagnostics",
            @"com.apple.PosterBoard": @"Wallpaper", @"com.apple.MercuryPoster": @"Wallpaper (Mercury)",
            @"com.apple.WallpaperKit.CollectionsPoster": @"Wallpaper Collections",
            @"com.apple.PhotosUIPrivate.PhotosPosterProvider": @"Photo Wallpaper",
            @"com.apple.chrono.WidgetRenderer-Default": @"Widgets", @"com.apple.ScreenshotServicesService": @"Screenshots",
            @"com.apple.Sharing.AirDrop": @"AirDrop", @"com.apple.AppleMediaServicesUI": @"Apple Media Services",
            @"com.apple.AppleMediaServices": @"Apple Media Services", @"com.apple.ClarityCamera": @"Assistive Access Camera",
            @"com.apple.ClarityPhotos": @"Assistive Access Photos", @"com.apple.SystemVoiceAssistant": @"Voice Assistant",
            @"com.apple.ShazamEventsApp": @"Shazam", @"com.apple.ScreenTimeWidgetApplication": @"Screen Time",
            @"com.apple.CBRemoteSetup": @"Remote Setup", @"com.apple.DemoApp": @"Demo", @"com.apple.AAUIViewService": @"Apple Account",
            @"com.apple.AccountAuthenticationDialog": @"Account Sign-In", @"com.apple.StoreKitUISceneService": @"App Store Sheets",
            @"com.apple.NewDeviceOutreachApp": @"New Device Setup", @"com.apple.PDUIApp": @"Printing", @"com.apple.EventViewService": @"Events",
            @"com.apple.MXUIService": @"Media Picker", @"com.apple.ctkui": @"Smart Card", @"com.apple.InCallService": @"Call Screen",
            @"com.apple.springboard": @"SpringBoard", @"com.apple.SafariViewService": @"Safari View", @"com.apple.mobilesms.compose": @"Message Compose",
            @"com.apple.CompanionViewService": @"Companion", @"com.apple.musicrecognition": @"Music Recognition",
            @"com.apple.FontInstallViewService": @"Font Install", @"com.apple.CMViewSrvc": @"Continuity Markup",
            @"com.apple.AppleCashStickerPackHost": @"Apple Cash Stickers", @"com.apple.TVSetupUIService": @"Apple TV Setup",
            @"com.apple.HearingApp": @"Hearing", @"com.apple.CompanionSetup": @"Companion Setup",
            @"com.apple.CarPlayWallpaper": @"CarPlay Wallpaper", @"com.apple.CloudKit.ShareBear": @"iCloud Sharing",
            @"com.apple.EnhancedLogging": @"Enhanced Logging", @"com.apple.tcc.AuthorizationPromptService": @"Privacy Prompts",
            @"com.apple.WebContentFilter.remoteUI.WebContentAnalysisUI": @"Content Filter",
            @"com.apple.SystemPaperViewService": @"Quick Note", @"com.apple.HeadphoneProxService": @"Headphones",
            @"com.apple.datadetectors.DDActionsService": @"Data Detectors", @"com.apple.ServicesPaymentAngel": @"Apple Pay",
            @"com.apple.HomeCaptiveViewService": @"Wi-Fi Login", @"com.apple.DiagnosticsService": @"Diagnostics",
            @"com.apple.CarTirePressure": @"Tire Pressure", @"com.apple.FCAuthenticationUI": @"Authentication",
            @"com.apple.icloud.FindMyDevice.FindMyExtensionContainer": @"Find My",
            @"com.apple.messages.RemoteAlerts": @"Messages Alerts",
            @"com.apple.AccessoryNotifications.SourceSelection": @"Accessory Source",
            @"com.apple.printcenter": @"Print Center", @"com.apple.BarcodeScanner": @"Code Scanner",
            @"com.apple.chrono.WidgetRenderer-Snapshots": @"Widget Snapshots",
            @"com.apple.AMSEngagementViewService": @"Apple Media Services",
            @"com.apple.appManagedFeatures.Restrictions": @"Restrictions", @"com.apple.CarRadio": @"Car Radio",
            @"com.apple.PassbookUIService": @"Wallet Sheets", @"com.apple.Spotlight": @"Spotlight", @"com.apple.InputUI": @"Keyboard",
        };
    });
    return names;
}

static NSString *wq_known_name_locked(NSString *bundleID)
{
    wq_load_ls_names_locked();
    return gLSDisplay[bundleID] ?: wq_builtin_names()[bundleID] ?: gLSBundleName[bundleID];
}

BOOL wq_display_names_loaded(void)
{
    @synchronized (wq_ls_lock()) { return gLSLoaded; }
}

void wq_load_display_names(void)
{
    @synchronized (wq_ls_lock()) { wq_load_ls_names_locked(); }
}

void wq_display_names_reset_miss(void)
{
    @synchronized (wq_ls_lock()) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:kWQLSMissKey];
        gLSNextRetryAt = 0;
        gLSFailureCount = 0;
    }
}

static NSString *const kWQBundleContainerRoot = @"/private/var/containers/Bundle/Application/";

// App bundle containers (<root>/<UUID>, holding Name.app) -> bundle id, built
// from the bundle paths; rebuilt when a new database snapshot is published.
static NSDictionary<NSString *, NSString *> *wq_bundle_containers_locked(void)
{
    static NSDictionary *source, *map;
    wq_load_ls_names_locked();
    if (map && source == gLSBundlePaths) return map;
    NSMutableDictionary *built = [NSMutableDictionary new];
    [gLSBundlePaths enumerateKeysAndObjectsUsingBlock:^(NSString *bid, NSString *path, BOOL *__unused stop) {
        if (![bid isKindOfClass:NSString.class] || ![path isKindOfClass:NSString.class]) return;
        NSString *app = path.stringByStandardizingPath;
        if ([app hasPrefix:@"/var/"]) app = [@"/private" stringByAppendingString:app];
        if (![app hasPrefix:kWQBundleContainerRoot] || ![app.pathExtension isEqualToString:@"app"]) return;
        NSString *container = app.stringByDeletingLastPathComponent;
        // Only <root>/<UUID>/Name.app: extensions and nested apps stay out.
        if (![container.stringByDeletingLastPathComponent isEqualToString:
              [kWQBundleContainerRoot substringToIndex:kWQBundleContainerRoot.length - 1]]) return;
        if (!built[container] || bid.length < [built[container] length]) built[container] = bid;
    }];
    source = gLSBundlePaths;
    map = [built copy];
    return map;
}

NSString *wq_bundle_id_for_container(NSString *path)
{
    if (!path.length) return nil;
    NSString *key = path.stringByStandardizingPath;
    if ([key hasPrefix:@"/var/"]) key = [@"/private" stringByAppendingString:key];
    @synchronized (wq_ls_lock()) {
        wq_load_ls_names_locked();
        NSString *bid = gLSContainers[key];
        if (!bid && [key hasPrefix:kWQBundleContainerRoot]) bid = wq_bundle_containers_locked()[key];
        return [bid isKindOfClass:NSString.class] ? bid : nil;
    }
}

NSString *wq_group_id_for_container(NSString *path)
{
    NSString *key = wq_group_key(path);
    if (!key) return nil;
    @synchronized (wq_ls_lock()) {
        wq_load_ls_names_locked();
        NSString *ident = gLSGroupIDs[key];
        return [ident isKindOfClass:NSString.class] ? ident : nil;
    }
}

NSArray<NSString *> *wq_ls_bundle_containers(void)
{
    @synchronized (wq_ls_lock()) {
        return [wq_bundle_containers_locked().allKeys sortedArrayUsingSelector:@selector(compare:)];
    }
}

// Apple's apps are named in WQ Files' language (the tables hold "Weather",
// "Stocks"…); every other app keeps its name exactly, even when it happens to
// match a UI key such as "Files" or "Delete" (review CR-31).
static NSString *wq_present_name(NSString *bundleID, NSString *name)
{
    return [bundleID hasPrefix:@"com.apple."] ? WQVerbatim(WQLocalized(name)) : WQVerbatim(name);
}

NSString *wq_display_name(NSString *bundleID)
{
    if (!bundleID) return nil;
    @synchronized (wq_ls_lock()) {
        NSString *name = wq_known_name_locked(bundleID);
        if (name) return wq_present_name(bundleID, name);
        // Unknown id: use the closest parent app (com.apple.news.widget -> News).
        NSArray *parts = [bundleID componentsSeparatedByString:@"."];
        for (NSInteger n = (NSInteger)parts.count - 1; n >= 2; n--) {
            NSString *prefix = [[parts subarrayWithRange:NSMakeRange(0, (NSUInteger)n)] componentsJoinedByString:@"."];
            NSString *parent = wq_known_name_locked(prefix);
            if (parent) {
                NSString *suffix = wq_safe_name(parts.lastObject);
                NSString *shown = wq_present_name(prefix, parent);
                return WQVerbatim(suffix.length ? [NSString stringWithFormat:@"%@ \u2013 %@", shown, suffix] : shown);
            }
        }
        return nil;
    }
}

NSArray<NSString *> *wq_ls_container_paths(NSString *storeHint)
{
    // No scan here, and the lock is only held to compare or publish a
    // snapshot (never during the read or parse): the container scan calls
    // this while a name load may be waiting for that scan.
    NSString *path = storeHint.length ? storeHint : [NSUserDefaults.standardUserDefaults stringForKey:kWQLSStoreKey];
    if (!path.length) return nil;
    // The published snapshot of this exact store: no second read or parse.
    struct stat current;
    if (wq_ls_candidate_info(path, &current)) {
        @synchronized (wq_ls_lock()) {
            if (gLSLoaded && gLSAllPaths && [path isEqualToString:gLSStorePath] &&
                wq_ls_signature_equal(wq_ls_signature(&current), gLSStoreSignature))
                return gLSContainers.count >= 2 ? gLSAllPaths : nil;
        }
    }
    struct stat before;
    NSString *error = nil;
    NSData *data = wq_ls_read_stable(path, &before, &error);
    if (!data) {
        wq_log(@"names: cannot read %@ (%@)", path, error);
        return nil;
    }
    NSDictionary *display = nil, *bundleName = nil, *containers = nil, *bundlePaths = nil;
    if (!wq_parse_ls_store(data, &display, &bundleName, &containers, &bundlePaths) || containers.count < 2) return nil;
    NSArray<NSString *> *all = wq_ls_all_paths(data, containers);
    NSDictionary<NSString *, NSString *> *groupIDs = wq_ls_group_ids_from_store(data);
    // A hint (a newer store found by the scan) or a changed remembered store
    // replaces the loaded names and maps too, not only the remembered path.
    @synchronized (wq_ls_lock()) {
        wq_ls_publish_locked(path, &before, display, bundleName, containers, bundlePaths, all, groupIDs);
    }
    return all;
}

NSString *wq_bundle_path_for_id(NSString *bundleID)
{
    if (!bundleID.length) return nil;
    @synchronized (wq_ls_lock()) {
        wq_load_ls_names_locked();
        NSString *path = gLSBundlePaths[bundleID];
        return [path isKindOfClass:NSString.class] ? path : nil;
    }
}
