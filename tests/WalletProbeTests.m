// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import "../WalletProbe/ProbeFS.h"
#import "../WalletProbe/WQAccess.h"
#import "../WalletProbe/ProbeRunner.h"
#include <assert.h>
#include <errno.h>

int main(void) {
    @autoreleasepool {
        // 1. Validate Card ID filter
        assert(![ProbeFS validCardID:@"short"]);
        assert(![ProbeFS validCardID:@"../../etc/passwd_padding_12345"]);
        assert([ProbeFS validCardID:@"ABCDEFGHIJKLMNOPQRST123456"]);

        // 2. Validate WQAccess group guardrail and preflight errno reporting
        NSDictionary *badGroup = [WQAccess acquire:@"/tmp"
                                             group:@"group.com.siriusrry.gestaltx"
                                     skipPreflight:NO];
        assert([badGroup[@"stage"] isEqualToString:@"unexpected-group"]);
        assert([badGroup[@"errno"] intValue] == EINVAL);

        NSDictionary *missing = [WQAccess acquire:@"/nonexistent-walletprobe-path-99999"
                                            group:kWalletProbeDedicatedGroup
                                    skipPreflight:NO];
        assert([missing[@"stage"] isEqualToString:@"preflight"]);
        assert([missing[@"errno"] intValue] == ENOENT);

        // 3. Validate ProbeFS inspect, firstCardIDIn, and canary in temporary directory
        NSString *tempRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
                              [@"walletprobe-test-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *err = nil;
        assert([fm createDirectoryAtPath:tempRoot withIntermediateDirectories:YES attributes:nil error:&err]);

        NSString *fakeCardID = @"CARDID_TEST_1234567890ABCD";
        NSString *fakePassDir = [tempRoot stringByAppendingPathComponent:[fakeCardID stringByAppendingString:@".pkpass"]];
        assert([fm createDirectoryAtPath:fakePassDir withIntermediateDirectories:NO attributes:nil error:&err]);

        NSString *sampleFile = [fakePassDir stringByAppendingPathComponent:@"sample.bin"];
        NSData *sampleBytes = [@"hello-walletprobe" dataUsingEncoding:NSUTF8StringEncoding];
        assert([sampleBytes writeToFile:sampleFile atomically:YES]);

        NSDictionary *dirInspect = [ProbeFS inspect:tempRoot];
        assert([dirInspect[@"statOK"] boolValue]);
        assert([dirInspect[@"listOK"] boolValue]);
        assert([dirInspect[@"entryCount"] unsignedIntegerValue] == 1);

        NSDictionary *fileInspect = [ProbeFS inspect:sampleFile];
        assert([fileInspect[@"statOK"] boolValue]);
        assert([fileInspect[@"readOK"] boolValue]);
        assert([fileInspect[@"bytesRead"] unsignedIntegerValue] == sampleBytes.length);

        NSString *discovered = [ProbeFS firstCardIDIn:tempRoot];
        assert([discovered isEqualToString:fakeCardID]);

        NSDictionary *canary = [ProbeFS canary:tempRoot];
        assert([canary[@"stage"] isEqualToString:@"passed"]);
        assert([canary[@"created"] boolValue]);
        assert([canary[@"initialVerified"] boolValue]);
        assert([canary[@"overwriteVerified"] boolValue]);
        assert([canary[@"renamed"] boolValue]);
        assert([canary[@"cleanupComplete"] boolValue]);

        // Ensure canary left no residual files
        NSDictionary *afterCanaryInspect = [ProbeFS inspect:tempRoot];
        assert([afterCanaryInspect[@"entryCount"] unsignedIntegerValue] == 1);

        // 4. Verify ProbeRunner target specs and redaction of user-supplied Card ID
        NSArray<NSDictionary *> *specs = [ProbeRunner singleCardTargetSpecsForCardID:fakeCardID includeCanary:YES];
        assert(specs.count == 12);
        for (NSDictionary *spec in specs) {
            NSString *actualPath = spec[@"actualPath"];
            NSString *displayPath = spec[@"displayPath"];
            assert([actualPath rangeOfString:fakeCardID].location != NSNotFound);
            assert([displayPath rangeOfString:fakeCardID].location == NSNotFound);
            assert([displayPath rangeOfString:@"<CARD_ID>"].location != NSNotFound);
        }
        NSString *json = [ProbeRunner formatReportJSON:@{@"specs": [specs valueForKey:@"displayPath"]}];
        assert([json rangeOfString:fakeCardID].location == NSNotFound);
        assert([json rangeOfString:@"<CARD_ID>.pkpass"].location != NSNotFound);

        [fm removeItemAtPath:tempRoot error:nil];
        printf("WalletProbeTests passed.\n");
    }
    return 0;
}
