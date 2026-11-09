// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ProbeFS : NSObject
+ (NSDictionary *)inspect:(NSString *)path;
+ (NSDictionary *)canary:(NSString *)directory;
+ (BOOL)validCardID:(NSString *)value;
+ (nullable NSString *)firstCardIDIn:(NSString *)cardsDirectory;
@end
NS_ASSUME_NONNULL_END
