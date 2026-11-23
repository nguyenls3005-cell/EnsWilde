// SPDX-License-Identifier: GPL-3.0-only
#import "MGImageReader.h"
#import <TargetConditionals.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <string.h>

static NSData *GXCopySection(const struct mach_header_64 *header, intptr_t slide,
                             const char *segment, const char *name, uint64_t *address) {
    const struct section_64 *section = getsectbynamefromheader_64(header, segment, name);
    if (!section || !section->size || section->size > 32 * 1024 * 1024) return nil;
    uintptr_t start = (uintptr_t)section->addr + (uintptr_t)slide;
    if (!start || start + section->size < start) return nil;
    if (address) *address = start;
    return [NSData dataWithBytes:(const void *)start length:(NSUInteger)section->size];
}

NSDictionary<NSString *, id> *GXCopyMobileGestaltImage(void) {
#if TARGET_OS_SIMULATOR
    return nil;
#else
    static NSDictionary *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *path = "/usr/lib/libMobileGestalt.dylib";
        if (!dlopen(path, RTLD_LAZY | RTLD_LOCAL)) return;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name || strcmp(name, path)) continue;
            const struct mach_header_64 *header = (const void *)_dyld_get_image_header(i);
            if (!header || header->magic != MH_MAGIC_64) return;
            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            uint64_t stringAddress = 0;
            NSData *strings = GXCopySection(header, slide, "__TEXT", "__cstring", &stringAddress);
            NSMutableArray<NSData *> *constants = [NSMutableArray array];
            const char *segments[] = {"__AUTH_CONST", "__DATA_CONST", "__DATA"};
            for (size_t j = 0; j < sizeof(segments) / sizeof(segments[0]); j++) {
                NSData *data = GXCopySection(header, slide, segments[j], "__const", NULL);
                if (data) [constants addObject:data];
            }
            if (strings && constants.count) {
                image = @{ @"strings": strings, @"stringAddress": @(stringAddress), @"constants": constants };
            }
            return;
        }
    });
    return image;
#endif
}
