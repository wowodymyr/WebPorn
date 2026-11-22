// libc++abi entry points that modern libc++ calls but the libc++abi on
// iOS 8/9 does not export.

#include <cstdlib>
#include <typeinfo>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 100000

extern "C" {

bool __cxa_uncaught_exception() noexcept;

unsigned int __cxa_uncaught_exceptions() noexcept
{
    return __cxa_uncaught_exception() ? 1 : 0;
}

// Only reached through std::make_exception_ptr/std::promise; WebKit builds
// with -fno-exceptions and never creates exception objects.
void* __cxa_init_primary_exception(void*, std::type_info*, void (*)(void*)) noexcept
{
    std::abort();
}

}

#endif
