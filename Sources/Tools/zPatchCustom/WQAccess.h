#import <Foundation/Foundation.h>
#import <sys/stat.h>
NS_ASSUME_NONNULL_BEGIN
typedef BOOL (*WQGrantFunc)(const char *path);
void wq_set_grant_callback(WQGrantFunc fn);
void wq_log(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
BOOL wq_grant(NSString *path);
BOOL wq_stat(NSString *path, struct stat *st);
NSData *_Nullable wq_read(NSString *path, NSUInteger maxBytes, NSString *_Nullable *_Nullable errorText);
NSArray<NSString *> *_Nullable wq_list(NSString *dir, NSString *_Nullable *_Nullable errorText);
@interface WQScanCancellation : NSObject
@property (atomic, readonly, getter=isCancelled) BOOL cancelled;
- (void)cancel;
@end
NSArray<NSString *> *_Nullable wq_enumerate(NSString *dir, int64_t maxInode, WQScanCancellation *_Nullable cancellation, void (^_Nullable progress)(int64_t, int64_t, NSUInteger));
void wq_enumerate_invalidate(void);
NS_ASSUME_NONNULL_END