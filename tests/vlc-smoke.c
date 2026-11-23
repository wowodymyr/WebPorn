// Play a URL with libvlc (MobileVLCKit's C API) into a memory buffer and report
// what came out: decoder setup, frame count / fps, duration, errors.
//   vlc-smoke <url> [seconds=10] [width=640] [height=360] [vlc-arg...]
// Log: libvlc messages at warning and above on stderr (-v for debug).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <unistd.h>
#include <vlc/vlc.h>

static unsigned width, height;
static void* pixels;
static volatile unsigned frames;
static volatile int ended;
static int verbose;

static double now(void)
{
    struct timeval tv; // iOS 8 has no clock_gettime
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1e6;
}

static void* lockFrame(void* opaque, void** planes)
{
    // RV32: one plane; I420 (CHROMA=I420): Y, U, V back to back.
    planes[0] = pixels;
    planes[1] = (char*)pixels + width * height;
    planes[2] = (char*)pixels + width * height * 5 / 4;
    return NULL;
}

static unsigned i420Format(void** opaque, char* chroma, unsigned* w, unsigned* h, unsigned* pitches, unsigned* lines)
{
    memcpy(chroma, "I420", 4);
    *w = width, *h = height;
    pitches[0] = width, pitches[1] = pitches[2] = width / 2;
    lines[0] = height, lines[1] = lines[2] = height / 2;
    return 1;
}

static void displayFrame(void* opaque, void* picture)
{
    frames++;
}

static void logMessage(void* data, int level, const libvlc_log_t* context, const char* format, va_list args)
{
    if (level < LIBVLC_WARNING && !verbose)
        return;
    const char* module;
    libvlc_log_get_context(context, &module, NULL, NULL);
    fprintf(stderr, "[%s] ", module ? module : "?");
    vfprintf(stderr, format, args);
    fputc('\n', stderr);
}

static void onEvent(const libvlc_event_t* event, void* data)
{
    switch (event->type) {
    case libvlc_MediaPlayerEndReached:
        ended = 1;
        break;
    case libvlc_MediaPlayerEncounteredError:
        ended = 2;
        break;
    default:
        break;
    }
}

int main(int argc, char** argv)
{
    if (argc > 1 && !strcmp(argv[1], "-v")) {
        verbose = 1;
        argv++, argc--;
    }
    if (argc < 2) {
        fprintf(stderr, "usage: %s [-v] <url> [seconds] [width] [height] [vlc-arg...]\n", argv[0]);
        return 1;
    }
    double seconds = argc > 2 ? atof(argv[2]) : 10;
    width = argc > 3 ? atoi(argv[3]) : 640;
    height = argc > 4 ? atoi(argv[4]) : 360;
    pixels = calloc(width * height, 4);

    printf("libvlc %s\n", libvlc_get_version());
    libvlc_instance_t* vlc = libvlc_new(argc > 5 ? argc - 5 : 0, (const char* const*)(argv + 5));
    if (!vlc) {
        printf("libvlc_new failed\n");
        return 1;
    }
    libvlc_log_set(vlc, logMessage, NULL);

    libvlc_media_t* media = libvlc_media_new_location(vlc, argv[1]);
    libvlc_media_player_t* player = libvlc_media_player_new_from_media(media);
    libvlc_video_set_callbacks(player, lockFrame, NULL, displayFrame, NULL);
    const char* chroma = getenv("CHROMA") ? getenv("CHROMA") : "RV32";
    if (!strcmp(chroma, "I420"))
        libvlc_video_set_format_callbacks(player, i420Format, NULL);
    else
        libvlc_video_set_format(player, chroma, width, height, width * 4);
    libvlc_event_manager_t* events = libvlc_media_player_event_manager(player);
    libvlc_event_attach(events, libvlc_MediaPlayerEndReached, onEvent, NULL);
    libvlc_event_attach(events, libvlc_MediaPlayerEncounteredError, onEvent, NULL);

    double start = now();
    libvlc_media_player_play(player);
    double firstFrame = 0;
    while (!ended && now() - start < seconds) {
        usleep(50000);
        if (!firstFrame && frames)
            firstFrame = now() - start;
    }
    double elapsed = now() - start;

    unsigned videoWidth = 0, videoHeight = 0;
    libvlc_video_get_size(player, 0, &videoWidth, &videoHeight);
    printf("result: %s\n", ended == 2 ? "error" : ended ? "ended" : "timeout (still playing)");
    printf("source %ux%u, duration %lld ms, position %lld ms\n", videoWidth, videoHeight,
        (long long)libvlc_media_player_get_length(player), (long long)libvlc_media_player_get_time(player));
    printf("frames %u in %.2f s (first after %.2f s): %.1f fps\n", frames, elapsed, firstFrame,
        frames / (elapsed - firstFrame > 0 ? elapsed - firstFrame : elapsed));
    libvlc_media_stats_t stats;
    if (libvlc_media_get_stats(media, &stats))
        printf("stats: decoded %d, displayed %d, lost %d, input %.0f kB/s\n", stats.i_decoded_video,
            stats.i_displayed_pictures, stats.i_lost_pictures, stats.f_input_bitrate * 8000 / 8);
    unsigned char* p = pixels;
    unsigned long sum = 0;
    for (unsigned i = 0; i < width * height * 4; i++)
        sum += p[i];
    printf("last frame mean byte %.1f\n", (double)sum / (width * height * 4));

    libvlc_media_player_stop(player);
    libvlc_media_player_release(player);
    libvlc_media_release(media);
    libvlc_release(vlc);
    return ended == 2;
}
