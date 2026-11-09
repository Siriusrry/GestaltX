// SPDX-License-Identifier: GPL-3.0-only
#import "ProbeFS.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>

@implementation ProbeFS
+ (BOOL)validCardID:(NSString *)value {
    if (value.length < 20 || value.length > 64) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_+=-"];
    return [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound;
}
+ (nullable NSString *)firstCardIDIn:(NSString *)cardsDirectory {
    DIR *dir = opendir(cardsDirectory.fileSystemRepresentation);
    if (!dir) return nil;
    NSString *found = nil;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        NSString *name = [NSString stringWithUTF8String:entry->d_name];
        if ([name hasSuffix:@".pkpass"]) {
            NSString *candidate = [name substringToIndex:name.length - 7];
            if ([self validCardID:candidate]) {
                found = candidate;
                break;
            }
        }
    }
    closedir(dir);
    return found;
}
+ (NSDictionary *)inspect:(NSString *)path {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) != 0)
        return @{@"statOK":@NO, @"statErrno":@(errno)};
    result[@"statOK"] = @YES;
    result[@"mode"] = @((unsigned int)(st.st_mode & 0777));
    result[@"uid"] = @(st.st_uid);
    if (S_ISDIR(st.st_mode)) {
        DIR *dir = opendir(path.fileSystemRepresentation);
        if (!dir) { result[@"listOK"] = @NO; result[@"listErrno"] = @(errno); return result; }
        NSUInteger count = 0;
        errno = 0;
        struct dirent *entry;
        while ((entry = readdir(dir))) {
            if (strcmp(entry->d_name, ".") && strcmp(entry->d_name, "..")) count++;
        }
        int error = errno;
        closedir(dir);
        result[@"listOK"] = @(error == 0);
        result[@"entryCount"] = @(count);
        if (error) result[@"listErrno"] = @(error);
    } else if (S_ISREG(st.st_mode)) {
        int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
        if (fd < 0) { result[@"readOK"] = @NO; result[@"readErrno"] = @(errno); return result; }
        // Read all bytes, bounded; never export file contents or hashes of private data.
        size_t total = 0;
        char buffer[8192];
        ssize_t n = 0;
        while (total <= 16 * 1024 * 1024 && (n = read(fd, buffer, sizeof(buffer))) > 0) total += n;
        int error = n < 0 ? errno : 0;
        close(fd);
        result[@"readOK"] = @(error == 0 && n == 0);
        result[@"bytesRead"] = @(total);
        if (error) result[@"readErrno"] = @(error);
        if (n > 0) result[@"sizeLimit"] = @YES;
    }
    return result;
}
+ (NSDictionary *)canary:(NSString *)directory {
    // The caller grants only a known Wallet directory. No pre-existing leaf is opened.
    int dirfd = open(directory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (dirfd < 0) return @{@"stage":@"open-directory", @"errno":@(errno), @"cleanupComplete":@YES};
    NSString *leaf = [@".walletprobe-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *renamed = [leaf stringByAppendingString:@"-renamed"];
    const char first[] = "WalletProbe temporary A\n";
    const char second[] = "WalletProbe temporary B\n";
    NSMutableDictionary *result = [@{@"stage":@"create", @"cleanupComplete":@YES} mutableCopy];
    int fd = openat(dirfd, leaf.UTF8String, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0600);
    if (fd < 0) { result[@"errno"] = @(errno); close(dirfd); return result; }
    BOOL originalExists = YES, renamedExists = NO;
    result[@"created"] = @YES;
    BOOL ok = YES;
    for (NSUInteger step = 0; step < 2 && ok; step++) {
        const char *bytes = step == 0 ? first : second;
        size_t length = sizeof(first) - 1;
        result[@"stage"] = step == 0 ? @"initial-write" : @"overwrite";
        errno = 0;
        if (step > 0 && (lseek(fd, 0, SEEK_SET) < 0 || ftruncate(fd, 0) != 0)) ok = NO;
        if (ok && (write(fd, bytes, length) != (ssize_t)length || fsync(fd) != 0)) ok = NO;
        int saved = errno;
        char readback[sizeof(first)] = {0};
        if (ok && (lseek(fd, 0, SEEK_SET) < 0 || read(fd, readback, length) != (ssize_t)length ||
                   memcmp(bytes, readback, length) != 0)) { ok = NO; saved = errno; }
        if (!ok) result[@"errno"] = @(saved);
        else result[step == 0 ? @"initialVerified" : @"overwriteVerified"] = @YES;
    }
    close(fd);
    if (ok) {
        result[@"stage"] = @"rename";
        if (renameatx_np(dirfd, leaf.UTF8String, dirfd, renamed.UTF8String, RENAME_EXCL) == 0) {
            originalExists = NO; renamedExists = YES; result[@"renamed"] = @YES;
        } else { result[@"errno"] = @(errno); ok = NO; }
    }
    BOOL cleaned = YES;
    if (originalExists && unlinkat(dirfd, leaf.UTF8String, 0) != 0) cleaned = NO;
    if (renamedExists && unlinkat(dirfd, renamed.UTF8String, 0) != 0) cleaned = NO;
    struct stat st;
    if (fstatat(dirfd, leaf.UTF8String, &st, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT) cleaned = NO;
    if (fstatat(dirfd, renamed.UTF8String, &st, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT) cleaned = NO;
    result[@"cleanupComplete"] = @(cleaned);
    if (!cleaned) {
        result[@"recoveryLeaf"] = originalExists ? leaf : renamed;
        result[@"stage"] = @"cleanup-failed";
    } else if (ok) result[@"stage"] = @"passed";
    close(dirfd);
    return result;
}
@end
