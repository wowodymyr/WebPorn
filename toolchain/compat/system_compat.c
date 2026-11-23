// libSystem entry points WebKit calls that iOS 8/9 lacks. Linked hidden into
// each WebPorn image, so these bind locally and never shadow system symbols.
// Declared with explicit Mach-O names to stay clear of the SDK prototypes.

#include <dlfcn.h>
#include <fcntl.h>
#include <mach-o/loader.h>
#include <mach/mach_time.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 100000

struct timespec;

// clock_gettime: the 9.3-SDK build routes it to wp_clock_gettime (time_compat.c);
// code built against a newer SDK references the real name.
int wp_clock_gettime(int, struct timespec*) __asm__("_wp_clock_gettime");
int wp_clock_gettime_real_name(int clock, struct timespec* ts) __asm__("_clock_gettime");
int wp_clock_gettime_real_name(int clock, struct timespec* ts) { return wp_clock_gettime(clock, ts); }

// mach_continuous_time (iOS 10): no sleep-inclusive clock before that.
uint64_t wp_mach_continuous_time(void) __asm__("_mach_continuous_time");
uint64_t wp_mach_continuous_time(void) { return mach_absolute_time(); }
uint64_t wp_mach_continuous_approximate_time(void) __asm__("_mach_continuous_approximate_time");
uint64_t wp_mach_continuous_approximate_time(void) { return mach_absolute_time(); }

// mkostemp/mkostemps (iOS 10): only O_CLOEXEC is meaningful here.
static int applyOFlags(int fd, int flags)
{
    if (fd >= 0 && (flags & O_CLOEXEC))
        fcntl(fd, F_SETFD, FD_CLOEXEC);
    return fd;
}
int wp_mkostemp(char* path, int flags) __asm__("_mkostemp");
int wp_mkostemp(char* path, int flags) { return applyOFlags(mkstemp(path), flags); }
int wp_mkostemps(char* path, int suffixLength, int flags) __asm__("_mkostemps");
int wp_mkostemps(char* path, int suffixLength, int flags) { return applyOFlags(mkstemps(path, suffixLength), flags); }

// os_log (iOS 10): WebKit logging is compiled out (WK26_ENGINE_DIAG=0); swallow it.
char wp_os_log_default[64] __asm__("__os_log_default");
char wp_os_log_default[64];
void* wp_os_log_create(const char* subsystem, const char* category) __asm__("__os_log_create");
void* wp_os_log_create(const char* subsystem, const char* category) { return wp_os_log_default; }
void wp_os_log_internal(void* dso, void* log, uint8_t type, const char* format, ...) __asm__("__os_log_internal");
void wp_os_log_internal(void* dso, void* log, uint8_t type, const char* format, ...) { }

bool wp_os_variant_allows_internal_security_policies(const char* subsystem) __asm__("_os_variant_allows_internal_security_policies");
bool wp_os_variant_allows_internal_security_policies(const char* subsystem) { return false; }

void wp_abort_with_reason(uint32_t, uint64_t, const char*, uint64_t) __asm__("_abort_with_reason");
void wp_abort_with_reason(uint32_t namespace_, uint64_t code, const char* reason, uint64_t flags) { abort(); }

// dyld introspection.
const struct mach_header* wp_dyld_image_header_containing_address(const void*) __asm__("_dyld_image_header_containing_address");
const struct mach_header* wp_dyld_image_header_containing_address(const void* address)
{
    Dl_info info;
    if (!dladdr(address, &info))
        return NULL;
    return (const struct mach_header*)info.dli_fbase;
}

const char* wp_dyld_shared_cache_file_path(void) __asm__("_dyld_shared_cache_file_path");
const char* wp_dyld_shared_cache_file_path(void) { return NULL; }

bool wp_dyld_get_shared_cache_uuid(uint8_t uuid[16]) __asm__("__dyld_get_shared_cache_uuid");
bool wp_dyld_get_shared_cache_uuid(uint8_t uuid[16]) { return false; }

bool wp_dyld_get_image_uuid(const struct mach_header*, uint8_t uuid[16]) __asm__("__dyld_get_image_uuid");
bool wp_dyld_get_image_uuid(const struct mach_header* header, uint8_t uuid[16])
{
    const struct load_command* command;
    if (header->magic == MH_MAGIC_64)
        command = (const struct load_command*)((const char*)header + sizeof(struct mach_header_64));
    else
        command = (const struct load_command*)(header + 1);
    for (uint32_t i = 0; i < header->ncmds; ++i) {
        if (command->cmd == LC_UUID) {
            memcpy(uuid, ((const struct uuid_command*)command)->uuid, 16);
            return true;
        }
        command = (const struct load_command*)((const char*)command + command->cmdsize);
    }
    return false;
}

// iOS 10 libc / libdispatch / libtrace / kernel calls WebCore makes.
int wp_timingsafe_bcmp(const void*, const void*, size_t) __asm__("_timingsafe_bcmp");
int wp_timingsafe_bcmp(const void* b1, const void* b2, size_t len)
{
    const unsigned char* p1 = b1;
    const unsigned char* p2 = b2;
    unsigned char diff = 0;
    for (size_t i = 0; i < len; i++)
        diff |= p1[i] ^ p2[i];
    return diff != 0;
}

// Only needed for objects created inactive (iOS 10 API); anything else is already
// active, and resuming it would over-resume.
void wp_dispatch_activate(void*) __asm__("_dispatch_activate");
void wp_dispatch_activate(void* object) { }

int wp_mach_memory_entry_ownership(unsigned, unsigned, int, int) __asm__("_mach_memory_entry_ownership");
int wp_mach_memory_entry_ownership(unsigned entry, unsigned owner, int ledgerTag, int ledgerFlags) { return 46; } // KERN_NOT_SUPPORTED

#endif

// Newer than iOS 10 too.
bool wp_os_feature_enabled_impl(const char*, const char*) __asm__("__os_feature_enabled_impl");
bool wp_os_feature_enabled_impl(const char* domain, const char* feature) { return false; }

int wp_os_fault_with_payload(uint32_t, uint64_t, void*, uint32_t, const char*, uint64_t) __asm__("_os_fault_with_payload");
int wp_os_fault_with_payload(uint32_t reasonNamespace, uint64_t reasonCode, void* payload, uint32_t payloadSize, const char* reasonString, uint64_t reasonFlags) { return 0; }
