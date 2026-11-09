// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface WQAccess : NSObject
+ (NSDictionary *)acquire:(NSString *)path group:(NSString *)group skipPreflight:(BOOL)skip;
+ (void)releaseHandle:(int64_t)handle;
@end
NS_ASSUME_NONNULL_END
