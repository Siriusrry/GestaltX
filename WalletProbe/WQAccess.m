// SPDX-License-Identifier: GPL-3.0-or-later
// Derived from worse_query, Copyright (C) 2026 Taj C (forcequit).
// Source: forcequitOS/worse_query, d1540e2; GestaltX 53d45ce.
// WalletProbe changes: structured stage diagnostics, explicit preflight bypass,
// exclusive dedicated-group use, reversible Caches relocation, crash recovery.
#import "WQAccess.h"
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>
#include <xpc/xpc.h>

static NSDictionary *Failure(NSString *stage, int error) {
    return @{@"stage":stage, @"errno":@(error), @"handle":@(-1)};
}
static BOOL Exists(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0;
}

@implementation WQAccess
+ (NSDictionary *)acquire:(NSString *)path group:(NSString *)group skipPreflight:(BOOL)skip {
    // A probe must never rearrange another application's shared data.
    if (![group isEqualToString:@"group.com.siriusrry.walletprobe"])
        return Failure(@"unexpected-group", EINVAL);
    struct stat st;
    if (!skip && lstat(path.fileSystemRepresentation, &st) != 0)
        return Failure(@"preflight", errno);
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [fm containerURLForSecurityApplicationGroupIdentifier:group];
    if (!root) return Failure(@"app-group", 0);
    NSString *library = [root.path stringByAppendingPathComponent:@"Library"];
    NSString *caches = [library stringByAppendingPathComponent:@"Caches"];
    NSString *backup = [library stringByAppendingPathComponent:@"Caches.walletprobe-original"];
    NSError *error = nil;
    if (![fm createDirectoryAtPath:library withIntermediateDirectories:YES attributes:nil error:&error])
        return Failure(@"group-library", (int)error.code);
    // Restore an interrupted attempt, removing ONLY its symlink, never its target.
    if (Exists(backup)) {
        if (lstat(caches.fileSystemRepresentation, &st) == 0) {
            if (!S_ISLNK(st.st_mode)) return Failure(@"recovery-conflict", EEXIST);
            if (unlink(caches.fileSystemRepresentation) != 0) return Failure(@"recovery-unlink", errno);
        } else if (errno != ENOENT) return Failure(@"recovery-stat", errno);
        if (rename(backup.fileSystemRepresentation, caches.fileSystemRepresentation) != 0)
            return Failure(@"recovery-rename", errno);
    }
    if (!Exists(caches) && ![fm createDirectoryAtPath:caches withIntermediateDirectories:NO attributes:nil error:&error])
        return Failure(@"group-caches", (int)error.code);
    if (lstat(caches.fileSystemRepresentation, &st) != 0 || !S_ISDIR(st.st_mode))
        return Failure(@"group-caches-type", EINVAL);

    void *mgr = dlopen("/usr/lib/system/libsystem_containermanager.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!mgr) return Failure(@"load-library", 0);
    void *(*create)(void) = dlsym(mgr, "container_query_create");
    void (*setClass)(void *, uint64_t) = dlsym(mgr, "container_query_set_class");
    void (*setIdentifiers)(void *, xpc_object_t) = dlsym(mgr, "container_query_set_group_identifiers");
    void (*setFlags)(void *, uint64_t) = dlsym(mgr, "container_query_operation_set_flags");
    void (*setPart)(void *, uint64_t) = dlsym(mgr, "container_query_operation_set_part");
    void *(*getResult)(void *) = dlsym(mgr, "container_query_get_single_result");
    void (*freeQuery)(void *) = dlsym(mgr, "container_query_free");
    char *(*copyToken)(void *) = dlsym(mgr, "container_copy_sandbox_token");
    int64_t (*consume)(const char *) = dlsym(RTLD_DEFAULT, "sandbox_extension_consume");
    int (*release)(int64_t) = dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (!create || !setClass || !setIdentifiers || !setFlags || !setPart ||
        !getResult || !freeQuery || !copyToken || !consume || !release) {
        dlclose(mgr); return Failure(@"resolve-api", 0);
    }
    void *query = create();
    if (!query) { dlclose(mgr); return Failure(@"create-query", 0); }
    setClass(query, 7);
    xpc_object_t identifier = xpc_string_create(group.UTF8String);
    setIdentifiers(query, identifier);
    setPart(query, 3);
    setFlags(query, 0x0000008000000000ULL); // Original worse_query iOS 27 flags.
    NSMutableDictionary *result = [Failure(@"prepare-link", 0) mutableCopy];
    BOOL moved = NO;
    if (rename(caches.fileSystemRepresentation, backup.fileSystemRepresentation) != 0) {
        result[@"errno"] = @(errno);
    } else {
        moved = YES;
        if (symlink(path.fileSystemRepresentation, caches.fileSystemRepresentation) != 0) {
            result[@"errno"] = @(errno);
        } else {
            errno = 0;
            void *container = getResult(query);
            int queryErrno = errno;
            result[@"queryResult"] = @(container != NULL);
            result[@"queryErrno"] = @(queryErrno);
            result[@"stage"] = @"query";
            if (container) {
                errno = 0;
                char *token = copyToken(container);
                result[@"tokenReturned"] = @(token != NULL);
                result[@"tokenErrno"] = @(errno);
                result[@"stage"] = @"token";
                if (token) {
                    errno = 0;
                    int64_t handle = consume(token);
                    result[@"consumeErrno"] = @(errno);
                    result[@"handle"] = @(handle);
                    result[@"stage"] = handle >= 0 ? @"granted" : @"consume";
                    free(token); // Never log or persist the token.
                }
            }
        }
    }
    freeQuery(query);
    BOOL restored = !moved;
    if (moved) {
        BOOL clear = NO;
        if (lstat(caches.fileSystemRepresentation, &st) == 0) {
            clear = S_ISLNK(st.st_mode) && unlink(caches.fileSystemRepresentation) == 0;
        } else { clear = errno == ENOENT; }
        restored = clear && rename(backup.fileSystemRepresentation, caches.fileSystemRepresentation) == 0;
    }
    result[@"groupCachesRestored"] = @(restored);
    if (!restored) {
        if ([result[@"handle"] longLongValue] >= 0) release([result[@"handle"] longLongValue]);
        result[@"handle"] = @(-1);
        result[@"stage"] = @"cleanup-failed";
    }
    dlclose(mgr);
    return result;
}
+ (void)releaseHandle:(int64_t)handle {
    int (*release)(int64_t) = dlsym(RTLD_DEFAULT, "sandbox_extension_release");
    if (handle >= 0 && release) release(handle);
}
@end
