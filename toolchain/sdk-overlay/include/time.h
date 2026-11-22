/* WebPorn SDK overlay: clock_gettime() and the CLOCK_* ids are iOS 10+.
   Below that, route them to wp_clock_gettime() in libwpcxxcompat. */
#include_next <time.h>

#if defined(__APPLE__) && !defined(CLOCK_REALTIME) \
    && defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 100000
#ifndef WP_TIME_OVERLAY
#define WP_TIME_OVERLAY 1
typedef enum {
    _CLOCK_REALTIME = 0,
#define CLOCK_REALTIME _CLOCK_REALTIME
    _CLOCK_MONOTONIC = 6,
#define CLOCK_MONOTONIC _CLOCK_MONOTONIC
    _CLOCK_MONOTONIC_RAW = 4,
#define CLOCK_MONOTONIC_RAW _CLOCK_MONOTONIC_RAW
    _CLOCK_UPTIME_RAW = 8,
#define CLOCK_UPTIME_RAW _CLOCK_UPTIME_RAW
} clockid_t;
#ifdef __cplusplus
extern "C" {
#endif
int clock_gettime(clockid_t, struct timespec*) __asm__("_wp_clock_gettime");
#ifdef __cplusplus
}
#endif
#endif
#endif
