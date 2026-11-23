// clock_gettime() for iOS 8/9 (the libc symbol is iOS 10+). Declared by
// sdk-overlay/include/time.h under the name wp_clock_gettime.

#include <errno.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
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
    case CLOCK_PROCESS_CPUTIME_ID: {
        struct rusage usage;
        if (getrusage(RUSAGE_SELF, &usage))
            return -1;
        ts->tv_sec = usage.ru_utime.tv_sec + usage.ru_stime.tv_sec;
        ts->tv_nsec = (usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) * 1000;
        if (ts->tv_nsec >= 1000000000) {
            ts->tv_sec++;
            ts->tv_nsec -= 1000000000;
        }
        return 0;
    }
    case CLOCK_THREAD_CPUTIME_ID: {
        thread_basic_info_data_t info;
        mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
        mach_port_t thread = mach_thread_self();
        kern_return_t kr = thread_info(thread, THREAD_BASIC_INFO, (thread_info_t)&info, &count);
        mach_port_deallocate(mach_task_self(), thread);
        if (kr != KERN_SUCCESS) {
            errno = EINVAL;
            return -1;
        }
        ts->tv_sec = info.user_time.seconds + info.system_time.seconds;
        ts->tv_nsec = (info.user_time.microseconds + info.system_time.microseconds) * 1000;
        if (ts->tv_nsec >= 1000000000) {
            ts->tv_sec++;
            ts->tv_nsec -= 1000000000;
        }
        return 0;
    }
    }
    errno = EINVAL;
    return -1;
}
#endif
