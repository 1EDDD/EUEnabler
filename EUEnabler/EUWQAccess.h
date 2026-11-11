#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EUWQAccessToken : NSObject
+ (nullable instancetype)grantDirectory:(NSString *)path
                                  error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(grant(directory:));
@end

NS_ASSUME_NONNULL_END
