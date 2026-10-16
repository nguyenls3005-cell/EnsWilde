//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//
@import UIKit;
#import "idevice.h"
#import "applist.h"
#import "mount.h"
#import "JITEnableContext.h"

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
#import "bad_query/bad_query.h"
#include <stdint.h>
#include <stdbool.h>
// MARK: - bad_query (sandbox escape)
// Source: https://github.com/forcequitOS/bad_query
int64_t bad_query(char* path, bool create, char *group_identifier, bool is_group);
char *bad_query_list(char *path, int64_t max_inode);
void bad_query_release(int64_t handle);