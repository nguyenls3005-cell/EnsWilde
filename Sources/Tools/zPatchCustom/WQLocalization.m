//
//  WQLocalization.m
//  WQ Files
//

#import "WQLocalization.h"

// An immutable string that the lookup helpers recognize and pass through.
@interface WQVerbatimString : NSString
@end

@implementation WQVerbatimString {
    NSString *_text;
}

- (instancetype)initWithText:(NSString *)text
{
    if ((self = [super init])) _text = [text copy];
    return self;
}

- (NSUInteger)length { return _text.length; }
- (unichar)characterAtIndex:(NSUInteger)index { return [_text characterAtIndex:index]; }
- (void)getCharacters:(unichar *)buffer range:(NSRange)range { [_text getCharacters:buffer range:range]; }
- (id)copyWithZone:(NSZone *)__unused zone { return self; }

@end

NSString *WQVerbatim(NSString *text)
{
    if (!text || [text isKindOfClass:WQVerbatimString.class]) return text;
    return [[WQVerbatimString alloc] initWithText:text];
}

BOOL WQIsVerbatim(NSString *text)
{
    return [text isKindOfClass:WQVerbatimString.class];
}

NSString *WQLocalized(NSString *key)
{
    if (!key.length || WQIsVerbatim(key)) return key;
    return NSLocalizedString(key, nil);
}

NSString *WQLocalizedNullable(NSString *text)
{
    return text ? WQLocalized(text) : nil;
}

NSString *WQLocalizedFormat(NSString *key, ...)
{
    va_list args;
    va_start(args, key);
    NSString *format = WQLocalized(key);
    NSString *text = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    return text;
}
