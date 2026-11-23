//
//  MGImageReader.m
//  EnsWilde
//

#import "MGImageReader.h"
#import <TargetConditionals.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <string.h>

static const uint64_t MGMaxSectionSizeBytes = 32ULL * 1024ULL * 1024ULL;

static NSData * _Nullable MGCopyMachOSection(const struct mach_header_64 *header,
                                             intptr_t slide,
                                             const char *segmentName,
                                             const char *sectionName,
                                             uint64_t * _Nullable outAddress) {
    if (!header || !segmentName || !sectionName) {
        return nil;
    }

    const struct section_64 *section = getsectbynamefromheader_64(header, segmentName, sectionName);
    if (!section || section->size == 0 || section->size > MGMaxSectionSizeBytes) {
        return nil;
    }

    uintptr_t baseAddr = (uintptr_t)section->addr;
    uintptr_t vmSlide = (uintptr_t)slide;
    if (vmSlide > UINTPTR_MAX - baseAddr) {
        return nil;
    }

    uintptr_t start = baseAddr + vmSlide;
    if (start == 0 || (uint64_t)section->size > (uint64_t)(UINTPTR_MAX - start)) {
        return nil;
    }

    if (outAddress != NULL) {
        *outAddress = (uint64_t)start;
    }

    return [NSData dataWithBytes:(const void *)start length:(NSUInteger)section->size];
}

NSDictionary<NSString *, id> * _Nullable MGCopyMobileGestaltImage(void) {
#if TARGET_OS_SIMULATOR
    return nil;
#else
    static NSDictionary<NSString *, id> *cachedImage = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        const char *dylibPath = "/usr/lib/libMobileGestalt.dylib";
        if (dlopen(dylibPath, RTLD_LAZY | RTLD_LOCAL) == NULL) {
            return;
        }

        uint32_t imageCount = _dyld_image_count();
        for (uint32_t i = 0; i < imageCount; i++) {
            const char *imageName = _dyld_get_image_name(i);
            if (!imageName || strcmp(imageName, dylibPath) != 0) {
                continue;
            }

            const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(i);
            if (!header || header->magic != MH_MAGIC_64) {
                return;
            }

            intptr_t slide = _dyld_get_image_vmaddr_slide(i);
            uint64_t stringAddress = 0;
            NSData *strings = MGCopyMachOSection(header, slide, "__TEXT", "__cstring", &stringAddress);
            if (!strings) {
                return;
            }

            NSMutableArray<NSData *> *constants = [NSMutableArray array];
            const char *constSegments[] = { "__AUTH_CONST", "__DATA_CONST", "__DATA" };
            size_t segmentCount = sizeof(constSegments) / sizeof(constSegments[0]);

            for (size_t idx = 0; idx < segmentCount; idx++) {
                NSData *sectionData = MGCopyMachOSection(header, slide, constSegments[idx], "__const", NULL);
                if (sectionData) {
                    [constants addObject:sectionData];
                }
            }

            if (constants.count > 0) {
                cachedImage = @{
                    @"strings": strings,
                    @"stringAddress": @(stringAddress),
                    @"constants": [constants copy]
                };
            }
            return;
        }
    });

    return cachedImage;
#endif
}
