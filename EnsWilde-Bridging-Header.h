//
//  EnsWilde-Bridging-Header.h
//  EnsWilde
//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

//
//  EnsWilde-Bridging-Header.h
//  EnsWilde
//

@import UIKit;
#import "idevice.h"
#import "applist.h"
#import "mount.h"
#import "JITEnableContext.h"

// --- AIRLIFT & GRAPPA ---
#import "airlift.h"
#import "GrappaHelper.h"

// Hàm cũ (Giữ lại để tránh lỗi link, nhưng đéo dùng trong logic mới)
long FindCacheDataOffset(const char *mgKey);

#pragma mark - Private API

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)arg1 ;
@end
LSApplicationWorkspace *LSApplicationWorkspaceDefaultWorkspace(void);

@interface UIDevice(Private)
@property(nonatomic, strong, readonly) NSString *buildVersion;
+ (BOOL)_hasHomeButton;
@end

#pragma mark - worse_query & pathleak
#include <stdint.h>
#include <stdbool.h>

int64_t worse_query(NSString *path, NSString *group, bool alt_flags, bool create_dir);
void    worse_query_release(int64_t handle);
NSArray *pathleak(NSString *filter, uint64_t max_inode);

#pragma mark - MGImageReader
NSDictionary<NSString *, id> * _Nullable MGCopyLoadedMobileGestaltImage(void);

// --- WQ LAUNCH SERVICES INTEGRATION ---
#import "source/tool/zPachCustom/WQLaunchServices.h"
#import "source/tool/zPachCustom/WQAccess.h"
#import "source/tool/zPachCustom/WQLocalization.h"