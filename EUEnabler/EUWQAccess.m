#import "EUWQAccess.h"
#import "EUWQAccessSafety.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <unistd.h>
#import <xpc/xpc.h>

typedef struct __SecTask *EUWQSecTaskRef;
extern EUWQSecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(EUWQSecTaskRef task,
                                                 CFStringRef entitlement,
                                                 CFErrorRef *error);

typedef void *(*EUWQCreateQuery)(void);
typedef void (*EUWQSetU64)(void *, uint64_t);
typedef void (*EUWQSetIds)(void *, xpc_object_t);
typedef void *(*EUWQGetResult)(void *);
typedef void (*EUWQFreeQuery)(void *);
typedef char *(*EUWQCopyToken)(void *);
typedef int64_t (*EUWQConsume)(const char *);
typedef int (*EUWQRelease)(int64_t);

static void EUWQSetError(NSError **error, NSInteger code, NSString *message) {
    if (!error) return;
    *error = [NSError errorWithDomain:@"EUWQAccess"
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey: message}];
}

static NSArray<NSString *> *EUWQApplicationGroups(void) {
    EUWQSecTaskRef task = SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) return @[];

    CFTypeRef value = SecTaskCopyValueForEntitlement(
        task, CFSTR("com.apple.security.application-groups"), NULL);
    CFRelease(task);

    if (!value) return @[];
    id bridged = CFBridgingRelease(value);
    if (![bridged isKindOfClass:NSArray.class]) return @[];

    NSMutableArray<NSString *> *groups = [NSMutableArray array];
    for (id item in (NSArray *)bridged) {
        if ([item isKindOfClass:NSString.class] && [item length] > 0) {
            [groups addObject:item];
        }
    }
    return groups;
}

static int64_t EUWQQueryToken(NSString *group, BOOL alternateFlags) {
    void *manager = dlopen("/usr/lib/system/libsystem_containermanager.dylib",
                           RTLD_NOW | RTLD_LOCAL);
    if (!manager) return -2;

    EUWQCreateQuery create =
        (EUWQCreateQuery)dlsym(manager, "container_query_create");
    EUWQSetU64 setClass =
        (EUWQSetU64)dlsym(manager, "container_query_set_class");
    EUWQSetIds setGroups =
        (EUWQSetIds)dlsym(manager, "container_query_set_group_identifiers");
    EUWQSetU64 setFlags =
        (EUWQSetU64)dlsym(manager, "container_query_operation_set_flags");
    EUWQSetU64 setPart =
        (EUWQSetU64)dlsym(manager, "container_query_operation_set_part");
    EUWQGetResult getResult =
        (EUWQGetResult)dlsym(manager, "container_query_get_single_result");
    EUWQFreeQuery freeQuery =
        (EUWQFreeQuery)dlsym(manager, "container_query_free");
    EUWQCopyToken copyToken =
        (EUWQCopyToken)dlsym(manager, "container_copy_sandbox_token");
    EUWQConsume consume =
        (EUWQConsume)dlsym(RTLD_DEFAULT, "sandbox_extension_consume");

    if (!create || !setClass || !setGroups || !setFlags || !setPart ||
        !getResult || !freeQuery || !copyToken || !consume) {
        dlclose(manager);
        return -2;
    }

    void *query = create();
    if (!query) {
        dlclose(manager);
        return -3;
    }

    char *token = NULL;
    int64_t handle = -4;

    @try {
        setClass(query, 7);
        xpc_object_t identifier = xpc_string_create(group.UTF8String);
        if (!identifier) {
            handle = -5;
        } else {
            setGroups(query, identifier);
            xpc_release(identifier);
            setPart(query, 3);
            setFlags(query, alternateFlags
                ? UINT64_C(0x0000000800000000)
                : UINT64_C(0x0000008000000000));

            void *result = getResult(query);
            token = result ? copyToken(result) : NULL;
            handle = token ? consume(token) : (result ? -6 : -5);
        }
    } @catch (NSException *exception) {
        handle = -7;
    } @finally {
        if (token) free(token);
        freeQuery(query);
        dlclose(manager);
    }
    return handle;
}

@interface EUWQAccessToken () {
    int64_t _handle;
}
- (instancetype)initWithHandle:(int64_t)handle;
@end

@implementation EUWQAccessToken

- (instancetype)initWithHandle:(int64_t)handle {
    self = [super init];
    if (self) _handle = handle;
    return self;
}

- (void)dealloc {
    if (_handle >= 0) {
        EUWQRelease releaseExtension =
            (EUWQRelease)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
        if (releaseExtension) releaseExtension(_handle);
        _handle = -1;
    }
}

+ (instancetype)grantDirectory:(NSString *)path error:(NSError **)error {
    if (![path hasPrefix:@"/"] || path.length < 2 ||
        [path containsString:@"/../"] || [path hasSuffix:@"/.."]) {
        EUWQSetError(error, 1, @"The target must be a canonical absolute directory path.");
        return nil;
    }

    if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 27) {
        EUWQSetError(error, 2, @"The SystemGroup route used by this build requires iOS 27 or later.");
        return nil;
    }

    NSArray<NSString *> *groups = EUWQApplicationGroups();
    if (groups.count == 0) {
        EUWQSetError(error, 3, @"No App Group entitlement was found. Re-sign with AltStore or SideStore and keep its App Group entitlement.");
        return nil;
    }

    NSString *target = path.stringByStandardizingPath;
    if ([target hasPrefix:@"/var/"]) {
        target = [@"/private" stringByAppendingString:target];
    }

    NSFileManager *files = NSFileManager.defaultManager;
    NSError *lastError = nil;

    for (NSString *group in groups) {
        NSURL *groupURL = [files containerURLForSecurityApplicationGroupIdentifier:group];
        if (!groupURL) continue;

        NSString *libraryPath =
            [groupURL.path stringByAppendingPathComponent:@"Library"];
        if (![files createDirectoryAtPath:libraryPath
              withIntermediateDirectories:YES attributes:nil error:&lastError]) {
            continue;
        }

        int library = WQOpenDirectoryNoLinks(libraryPath);
        if (library < 0) continue;

        int lock = WQOpenRegularAt(library, ".eu-enabler-wq-lock",
                                   O_RDWR | O_CREAT, 0600);
        if (lock < 0 || flock(lock, LOCK_EX | LOCK_NB) != 0) {
            if (lock >= 0) close(lock);
            close(library);
            continue;
        }

        int64_t handle = -8;
        @try {
            if (WQCacheSwapBegin(library, target)) {
                handle = EUWQQueryToken(group, NO);
                if (handle < 0) {
                    handle = EUWQQueryToken(group, YES);
                }
            }
        } @catch (NSException *exception) {
            handle = -9;
        } @finally {
            if (!WQCacheSwapRecover(library)) {
                if (handle >= 0) {
                    EUWQRelease releaseExtension =
                        (EUWQRelease)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
                    if (releaseExtension) releaseExtension(handle);
                }
                handle = -10;
            }
            close(lock);
            close(library);
        }

        if (handle >= 0) {
            int directory = open(target.fileSystemRepresentation,
                                 O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (directory >= 0) {
                close(directory);
                return [[EUWQAccessToken alloc] initWithHandle:handle];
            }

            EUWQRelease releaseExtension =
                (EUWQRelease)dlsym(RTLD_DEFAULT, "sandbox_extension_release");
            if (releaseExtension) releaseExtension(handle);
        }
    }

    EUWQSetError(error, 4, lastError.localizedDescription ?: @"worse_query could not obtain verified access to the eligibility SystemGroup directory.");
    return nil;
}
@end
