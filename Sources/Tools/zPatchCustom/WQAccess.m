#import "WQAccess.h"
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <string.h>
#include <unistd.h>

static WQGrantFunc gGrantFunc = NULL;
void wq_set_grant_callback(WQGrantFunc fn) { gGrantFunc = fn; }
BOOL wq_grant(NSString *path) {
    if (!gGrantFunc || !path.length) return NO;
    return gGrantFunc(path.fileSystemRepresentation);
}
void wq_log(NSString *format, ...) {
    va_list args; va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[wqfiles] %@", line);
}
static BOOL wq_is_denied(int e) { return e == EPERM || e == EACCES; }
BOOL wq_stat(NSString *path, struct stat *st) {
    if (!path.length) return NO;
    if (lstat(path.fileSystemRepresentation, st) == 0) return YES;
    if (wq_is_denied(errno) && wq_grant(path) && lstat(path.fileSystemRepresentation, st) == 0) return YES;
    return NO;
}
static int wq_open_retry(NSString *path, int flags) {
    int fd = open(path.fileSystemRepresentation, flags | O_CLOEXEC);
    if (fd < 0 && wq_is_denied(errno)) {
        if (wq_grant(path.stringByDeletingLastPathComponent)) fd = open(path.fileSystemRepresentation, flags | O_CLOEXEC);
        if (fd < 0 && wq_grant(path)) fd = open(path.fileSystemRepresentation, flags | O_CLOEXEC);
    }
    return fd;
}
NSData *wq_read(NSString *path, NSUInteger maxBytes, NSString **errorText) {
    int fd = wq_open_retry(path, O_RDONLY);
    if (fd < 0) { if (errorText) *errorText = @(strerror(errno)); return nil; }
    NSMutableData *data = [NSMutableData new];
    uint8_t buf[65536];
    for (;;) {
        size_t want = sizeof(buf);
        if (maxBytes && data.length + want > maxBytes) want = maxBytes - data.length;
        if (want == 0) break;
        ssize_t n = read(fd, buf, want);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errorText) *errorText = @(strerror(errno));
            close(fd); return nil;
        }
        if (n == 0) break;
        [data appendBytes:buf length:(NSUInteger)n];
    }
    close(fd);
    return data;
}
NSArray<NSString *> *wq_list(NSString *dir, NSString **errorText) {
    NSError *error = nil;
    NSArray *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:&error];
    if (!items) {
        BOOL granted = wq_grant(dir) || wq_grant(dir.stringByDeletingLastPathComponent);
        if (granted) {
            error = nil;
            items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:&error];
        }
    }
    if (!items && errorText) *errorText = error.localizedDescription;
    return items;
}
@implementation WQScanCancellation { _Atomic BOOL _c; }
- (BOOL)isCancelled { return atomic_load_explicit(&_c, memory_order_relaxed); }
- (void)cancel { atomic_store_explicit(&_c, YES, memory_order_relaxed); }
@end
NSArray<NSString *> *wq_enumerate(NSString *dir, int64_t maxInode, WQScanCancellation *cancellation, void (^progress)(int64_t, int64_t, NSUInteger)) { return nil; }
void wq_enumerate_invalidate(void) {}