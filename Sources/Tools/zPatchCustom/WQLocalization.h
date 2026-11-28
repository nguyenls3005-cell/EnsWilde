#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSString *WQVerbatim(NSString *text);
BOOL WQIsVerbatim(NSString *text);
NSString *WQLocalized(NSString *key);
NSString *_Nullable WQLocalizedNullable(NSString *_Nullable text);
NSString *WQLocalizedFormat(NSString *key, ...) NS_FORMAT_FUNCTION(1, 2);
NS_ASSUME_NONNULL_END