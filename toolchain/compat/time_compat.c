// clock_gettime() for iOS 8/9 (the libc symbol is iOS 10+). Declared by
// sdk-overlay/include/time.h under the name wp_clock_gettime.

#include <errno.h>
#include <mach/mach_time.h>
#include <sys/time.h>
#include <time.h>

#if defined(WP_TIME_OVERLAY)
int clock_gettime(clockid_t clock, struct timespec* ts)
{
    switch (clock) {
    case CLOCK_REALTIME: {
        struct timeval tv;
        if (gettimeofday(&tv, NULL))
            return -1;
        ts->tv_sec = tv.tv_sec;
        ts->tv_nsec = tv.tv_usec * 1000;
        return 0;
    }
    case CLOCK_MONOTONIC:
    case CLOCK_MONOTONIC_RAW:
    case CLOCK_UPTIME_RAW: {
        static mach_timebase_info_data_t timebase;
        if (!timebase.denom)
            mach_timebase_info(&timebase);
        unsigned long long ns = mach_absolute_time() * timebase.numer / timebase.denom;
        ts->tv_sec = ns / 1000000000ull;
        ts->tv_nsec = ns % 1000000000ull;
        return 0;
    }
    }
    errno = EINVAL;
    return -1;
}
#endif
