// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const kWalletProbeDedicatedGroup;

@interface ProbeRunner : NSObject
+ (NSArray<NSDictionary *> *)singleCardTargetSpecsForCardID:(NSString *)cardID
                                              includeCanary:(BOOL)includeCanary;
+ (NSDictionary *)runProbeWithCardID:(nullable NSString *)rawCardID
                       includeCanary:(BOOL)includeCanary;
+ (NSString *)formatReportJSON:(NSDictionary *)report;
+ (nullable NSString *)writeReportToDocuments:(NSDictionary *)report;
@end

NS_ASSUME_NONNULL_END
