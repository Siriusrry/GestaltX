// SPDX-License-Identifier: GPL-3.0-or-later
#import "ProbeRunner.h"
#import "WQAccess.h"
#import "ProbeFS.h"
#include <errno.h>

NSString *const kWalletProbeDedicatedGroup = @"group.com.siriusrry.walletprobe";

static BOOL InspectSucceeded(NSDictionary *inspect) {
    return [inspect[@"listOK"] boolValue] || [inspect[@"readOK"] boolValue];
}

static NSString *ClassifyAttempt(NSDictionary *attempt, NSDictionary * _Nullable afterInspect) {
    if (afterInspect && InspectSucceeded(afterInspect)) return @"read-verified";
    NSString *stage = attempt[@"stage"] ?: @"unknown";
    if ([stage isEqualToString:@"cleanup-failed"]) return @"cleanup-failed";
    if ([stage isEqualToString:@"preflight"]) {
        int code = [attempt[@"errno"] intValue];
        if (code == EACCES || code == EPERM) return @"preflight-permission-denied";
        if (code == ENOENT) return @"preflight-enoent";
        return @"preflight-failed";
    }
    if ([stage isEqualToString:@"query"] && ![attempt[@"queryResult"] boolValue]) return @"query-rejected";
    if ([stage isEqualToString:@"token"] && ![attempt[@"tokenReturned"] boolValue]) return @"no-token";
    if ([stage isEqualToString:@"consume"]) return @"consume-failed";
    if ([stage isEqualToString:@"granted"]) return @"handle-granted-but-fs-denied";
    return stage;
}

@implementation ProbeRunner

+ (NSArray<NSDictionary *> *)singleCardTargetSpecsForCardID:(NSString *)cardID
                                              includeCanary:(BOOL)includeCanary {
    if (![ProbeFS validCardID:cardID]) return @[];
    NSArray<NSDictionary *> *roots = @[
        @{@"tag": @"var", @"prefix": @"/var/mobile/Library/Passes/Cards"},
        @{@"tag": @"private-var", @"prefix": @"/private/var/mobile/Library/Passes/Cards"}
    ];
    NSArray<NSDictionary *> *suffixes = @[
        @{@"key": @"pkpass-dir", @"rel": @".pkpass", @"canary": @(includeCanary)},
        @{@"key": @"bg-3x-png", @"rel": @".pkpass/cardBackgroundCombined@3x.png", @"canary": @NO},
        @{@"key": @"bg-2x-png", @"rel": @".pkpass/cardBackgroundCombined@2x.png", @"canary": @NO},
        @{@"key": @"bg-pdf", @"rel": @".pkpass/cardBackgroundCombined.pdf", @"canary": @NO},
        @{@"key": @"cache-dir", @"rel": @".cache", @"canary": @NO},
        @{@"key": @"pkcache-dir", @"rel": @".pkcache", @"canary": @NO},
    ];
    NSMutableArray<NSDictionary *> *specs = [NSMutableArray array];
    for (NSDictionary *root in roots) {
        for (NSDictionary *suf in suffixes) {
            NSString *name = [NSString stringWithFormat:@"card-%@-%@", suf[@"key"], root[@"tag"]];
            NSString *actual = [NSString stringWithFormat:@"%@/%@%@", root[@"prefix"], cardID, suf[@"rel"]];
            NSString *redacted = [NSString stringWithFormat:@"%@/<CARD_ID>%@", root[@"prefix"], suf[@"rel"]];
            [specs addObject:@{
                @"name": name,
                @"actualPath": actual,
                @"displayPath": redacted,
                @"canary": suf[@"canary"]
            }];
        }
    }
    return specs;
}

+ (NSDictionary *)probeSingleTargetNamed:(NSString *)name
                              actualPath:(NSString *)actualPath
                             displayPath:(NSString *)displayPath
                             allowCanary:(BOOL)allowCanary
                          discoveredCard:(NSString * _Nullable * _Nullable)discoveredCard
                           cleanupFailed:(BOOL *)cleanupFailed {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    entry[@"name"] = name;
    entry[@"path"] = displayPath;
    NSDictionary *before = [ProbeFS inspect:actualPath];
    entry[@"beforeWQ"] = before;

    NSDictionary *preflightAttempt = [WQAccess acquire:actualPath
                                                 group:kWalletProbeDedicatedGroup
                                         skipPreflight:NO];
    entry[@"preflightAttempt"] = preflightAttempt;
    if ([preflightAttempt[@"groupCachesRestored"] isEqual:@NO] ||
        [preflightAttempt[@"stage"] isEqualToString:@"cleanup-failed"]) {
        *cleanupFailed = YES;
        entry[@"effectiveReadAccess"] = @NO;
        entry[@"failureBoundary"] = @"cleanup-failed";
        return entry;
    }

    NSDictionary *afterPreflight = nil;
    int64_t handle = [preflightAttempt[@"handle"] longLongValue];
    if (handle >= 0) {
        afterPreflight = [ProbeFS inspect:actualPath];
        entry[@"afterPreflightInspect"] = afterPreflight;
        if (discoveredCard && !*discoveredCard && [afterPreflight[@"listOK"] boolValue]) {
            *discoveredCard = [ProbeFS firstCardIDIn:actualPath];
        }
        if (allowCanary && [afterPreflight[@"listOK"] boolValue]) {
            entry[@"canary"] = [ProbeFS canary:actualPath];
        }
        [WQAccess releaseHandle:handle];
    }

    NSDictionary *skipAttempt = nil;
    NSDictionary *afterSkip = nil;
    if ([preflightAttempt[@"stage"] isEqualToString:@"preflight"]) {
        skipAttempt = [WQAccess acquire:actualPath
                                  group:kWalletProbeDedicatedGroup
                          skipPreflight:YES];
        entry[@"skipPreflightAttempt"] = skipAttempt;
        if ([skipAttempt[@"groupCachesRestored"] isEqual:@NO] ||
            [skipAttempt[@"stage"] isEqualToString:@"cleanup-failed"]) {
            *cleanupFailed = YES;
            entry[@"effectiveReadAccess"] = @NO;
            entry[@"failureBoundary"] = @"cleanup-failed";
            return entry;
        }
        int64_t skipHandle = [skipAttempt[@"handle"] longLongValue];
        if (skipHandle >= 0) {
            afterSkip = [ProbeFS inspect:actualPath];
            entry[@"afterSkipPreflightInspect"] = afterSkip;
            if (discoveredCard && !*discoveredCard && [afterSkip[@"listOK"] boolValue]) {
                *discoveredCard = [ProbeFS firstCardIDIn:actualPath];
            }
            if (allowCanary && !entry[@"canary"] && [afterSkip[@"listOK"] boolValue]) {
                entry[@"canary"] = [ProbeFS canary:actualPath];
            }
            [WQAccess releaseHandle:skipHandle];
        }
    }
    if (allowCanary && !entry[@"canary"]) {
        entry[@"canary"] = @{@"skipped": @"directory-read-not-verified"};
    }

    BOOL readVerified = InspectSucceeded(before) ||
                        (afterPreflight && InspectSucceeded(afterPreflight)) ||
                        (afterSkip && InspectSucceeded(afterSkip));
    entry[@"effectiveReadAccess"] = @(readVerified);
    if (readVerified) {
        entry[@"failureBoundary"] = @"none";
    } else if (skipAttempt) {
        entry[@"failureBoundary"] = ClassifyAttempt(skipAttempt, afterSkip);
        entry[@"preflightBoundary"] = ClassifyAttempt(preflightAttempt, afterPreflight);
    } else {
        entry[@"failureBoundary"] = ClassifyAttempt(preflightAttempt, afterPreflight);
    }
    return entry;
}

+ (NSDictionary *)runProbeWithCardID:(nullable NSString *)rawCardID
                       includeCanary:(BOOL)includeCanary {
    NSMutableDictionary *report = [NSMutableDictionary dictionary];
    report[@"schemaVersion"] = @1;
    NSISO8601DateFormatter *iso = [[NSISO8601DateFormatter alloc] init];
    report[@"timestampUTC"] = [iso stringFromDate:[NSDate date]];
    report[@"bundleID"] = NSBundle.mainBundle.bundleIdentifier ?: @"unknown";
    report[@"dedicatedGroup"] = kWalletProbeDedicatedGroup;
    report[@"osVersion"] = NSProcessInfo.processInfo.operatingSystemVersionString ?: @"unknown";
    report[@"mode"] = includeCanary ? @"read+canary" : @"read-only";

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSMutableDictionary *selfChecks = [NSMutableDictionary dictionary];
    if (docs) {
        selfChecks[@"documentsInspect"] = [ProbeFS inspect:docs];
        if (includeCanary) {
            selfChecks[@"documentsCanary"] = [ProbeFS canary:docs];
        }
    }
    NSURL *groupURL = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:kWalletProbeDedicatedGroup];
    selfChecks[@"appGroupResolved"] = @(groupURL != nil);
    if (groupURL.path) {
        selfChecks[@"appGroupInspect"] = [ProbeFS inspect:groupURL.path];
    }
    report[@"selfChecks"] = selfChecks;

    NSMutableArray *targets = [NSMutableArray array];
    BOOL cleanupFailed = NO;
    NSString *discoveredCardID = nil;

    if (docs && !cleanupFailed) {
        [targets addObject:[self probeSingleTargetNamed:@"control-self-documents"
                                             actualPath:docs
                                            displayPath:@"<APP_SANDBOX>/Documents"
                                            allowCanary:NO
                                         discoveredCard:NULL
                                          cleanupFailed:&cleanupFailed]];
    }

    NSArray<NSDictionary *> *fixedTargets = @[
        @{@"name": @"control-mobilegestalt-var",
          @"path": @"/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist",
          @"canary": @NO, @"discoverCards": @NO},
        @{@"name": @"control-mobilegestalt-private-var",
          @"path": @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist",
          @"canary": @NO, @"discoverCards": @NO},
        @{@"name": @"wallet-passes-var",
          @"path": @"/var/mobile/Library/Passes",
          @"canary": @(includeCanary), @"discoverCards": @NO},
        @{@"name": @"wallet-passes-private-var",
          @"path": @"/private/var/mobile/Library/Passes",
          @"canary": @(includeCanary), @"discoverCards": @NO},
        @{@"name": @"wallet-cards-var",
          @"path": @"/var/mobile/Library/Passes/Cards",
          @"canary": @(includeCanary), @"discoverCards": @YES},
        @{@"name": @"wallet-cards-private-var",
          @"path": @"/private/var/mobile/Library/Passes/Cards",
          @"canary": @(includeCanary), @"discoverCards": @YES},
    ];

    for (NSDictionary *item in fixedTargets) {
        if (cleanupFailed) break;
        BOOL discover = [item[@"discoverCards"] boolValue];
        [targets addObject:[self probeSingleTargetNamed:item[@"name"]
                                             actualPath:item[@"path"]
                                            displayPath:item[@"path"]
                                            allowCanary:[item[@"canary"] boolValue]
                                         discoveredCard:discover ? &discoveredCardID : NULL
                                          cleanupFailed:&cleanupFailed]];
    }

    NSString *trimmedInput = [rawCardID stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmedInput hasSuffix:@".pkpass"]) {
        trimmedInput = [trimmedInput substringToIndex:trimmedInput.length - 7];
    }
    NSString *activeCardID = nil;
    if (trimmedInput.length > 0) {
        if ([ProbeFS validCardID:trimmedInput]) {
            activeCardID = trimmedInput;
            report[@"cardIDSource"] = @"user-supplied";
            report[@"cardIDLength"] = @(activeCardID.length);
        } else {
            report[@"cardIDSource"] = @"invalid-user-input";
        }
    } else if (discoveredCardID) {
        activeCardID = discoveredCardID;
        report[@"cardIDSource"] = @"auto-discovered-from-cards-dir";
        report[@"cardIDLength"] = @(activeCardID.length);
    } else {
        report[@"cardIDSource"] = @"none";
    }

    if (activeCardID && !cleanupFailed) {
        NSArray<NSDictionary *> *cardSpecs = [self singleCardTargetSpecsForCardID:activeCardID
                                                                    includeCanary:includeCanary];
        for (NSDictionary *spec in cardSpecs) {
            if (cleanupFailed) break;
            [targets addObject:[self probeSingleTargetNamed:spec[@"name"]
                                                 actualPath:spec[@"actualPath"]
                                                displayPath:spec[@"displayPath"]
                                                allowCanary:[spec[@"canary"] boolValue]
                                             discoveredCard:NULL
                                              cleanupFailed:&cleanupFailed]];
        }
    }

    report[@"abortedForCleanupFailure"] = @(cleanupFailed);
    report[@"targets"] = targets;
    return report;
}

+ (NSString *)formatReportJSON:(NSDictionary *)report {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:report
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:&error];
    if (!data) {
        return [NSString stringWithFormat:@"{\"serializationError\": \"%@\"}", error.localizedDescription];
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

+ (nullable NSString *)writeReportToDocuments:(NSDictionary *)report {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docs) return nil;
    NSString *path = [docs stringByAppendingPathComponent:@"walletprobe-report.json"];
    NSString *json = [self formatReportJSON:report];
    NSError *error = nil;
    if (![json writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return nil;
    }
    return path;
}

@end
