// libWebPornMedia: wpmedia.h over libVLC (MobileVLCKit 3.5.1's C API).
//
// Video goes through libVLC's own iOS output (VideoToolbox decode, OpenGL ES
// into a UIView, frames never touch the CPU): the only path the A6 plays 720p /
// 1080p30 on (the vmem callbacks top out around 20 fps, tests/vlc-smoke.c).
// That UIView sits in a plain CALayer, which is what WebCore puts into the page.
//
// UIKit work happens on the main thread, asynchronously: WebCore calls in on the
// WebThread, often while the main thread waits for the web lock, so a
// dispatch_sync to the main queue could deadlock. For the same reason stopping
// (libVLC's video output closes with a dispatch_sync to the main queue) runs on
// a background queue.

#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <vlc/vlc.h>
#include "wpmedia.h"

// MARK: - Debug log

// /var/webporn/wpmedia-debug present: events and decisions to wpmedia.log.
static void debugLog(const char* format, ...) __attribute__((format(printf, 1, 2)));
static void debugLog(const char* format, ...)
{
    static FILE* file;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!access("/var/webporn/wpmedia-debug", F_OK))
            file = fopen("/var/mobile/Media/webporn/wpmedia-events.log", "w");
    });
    if (!file)
        return;
    static CFAbsoluteTime start;
    if (!start)
        start = CFAbsoluteTimeGetCurrent();
    fprintf(file, "%7.3f ", CFAbsoluteTimeGetCurrent() - start);
    va_list args;
    va_start(args, format);
    vfprintf(file, format, args);
    va_end(args);
    fputc('\n', file);
    fflush(file);
}

// MARK: - Host layer

// Keeps libVLC's drawable view the size of the layer WebCore lays out.
@interface WPMediaLayer : CALayer
@property (nonatomic, strong) UIView* drawable;
@end

@implementation WPMediaLayer

- (void)layoutSublayers
{
    [super layoutSublayers];
    CGRect bounds = self.bounds;
    UIView* drawable = self.drawable;
    if (!drawable)
        return;
    void (^resize)(void) = ^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        drawable.frame = bounds;
        // libVLC sizes its OpenGL view to the screen when the drawable is still
        // empty, and autoresizing only adds the difference afterwards.
        for (UIView* subview in drawable.subviews)
            subview.frame = drawable.bounds;
        [drawable layoutIfNeeded];
        [CATransaction commit];
    };
    if ([NSThread isMainThread])
        resize();
    else
        dispatch_async(dispatch_get_main_queue(), resize);
}

@end

// MARK: - Player

struct wpmedia_player {
    wpmedia_client client;
    libvlc_media_player_t* player;
    libvlc_media_t* media;
    void* layer; // WPMediaLayer, retained
    dispatch_queue_t queue; // serializes control calls and metadata queries
    int ready; // drawable attached and media set
    int wantsPlaying;
    double pendingSeek; // < 0: none
    double seekTarget; // < 0: none; time updates from before it are dropped
    CFAbsoluteTime seekIssued;
    float volume;
    int muted;
    float rate;
    double duration;
    unsigned width, height;
    int hasVideo, hasAudio;
};

static libvlc_instance_t* sharedInstance(void)
{
    static libvlc_instance_t* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char* args[] = { "--no-video-title-show", "--no-stats", "--network-caching=1000" };
        instance = libvlc_new(sizeof(args) / sizeof(*args), args);
    });
    return instance;
}

int wpmedia_abi_version(void)
{
    return WPMEDIA_ABI_VERSION;
}

// MARK: - Types

static int caseInsensitiveIn(const char* value, const char* const* list)
{
    for (; *list; list++) {
        if (!strcasecmp(value, *list))
            return 1;
    }
    return 0;
}

static int knownCodec(const char* codec, size_t length)
{
    // Prefixes of RFC 6381 codec strings libVLC decodes fast enough on an A6.
    static const char* const prefixes[] = { "avc1", "avc3", "mp4a", "hev1", "hvc1", "vp8", "vp08", "vp9", "vp09",
        "opus", "vorbis", "flac", "theora", "mp3", "mp4v", "ac-3", "ec-3", "alac", NULL };
    for (const char* const* prefix = prefixes; *prefix; prefix++) {
        size_t prefixLength = strlen(*prefix);
        if (length >= prefixLength && !strncasecmp(codec, *prefix, prefixLength))
            return 1;
    }
    return 0;
}

wpmedia_support wpmedia_supports(const char* container, const char* codecs)
{
    static const char* const containers[] = { "video/mp4", "video/x-m4v", "video/quicktime", "video/webm", "audio/webm",
        "video/ogg", "audio/ogg", "application/ogg", "audio/mpeg", "audio/mp3", "audio/mp4", "audio/x-m4a", "audio/aac",
        "audio/aacp", "audio/wav", "audio/x-wav", "audio/wave", "audio/flac", "audio/x-flac", "video/x-matroska",
        "audio/x-matroska", "video/3gpp", "audio/3gpp", "application/vnd.apple.mpegurl", "application/x-mpegurl",
        "audio/mpegurl", "audio/x-mpegurl", NULL };
    if (!container || !caseInsensitiveIn(container, containers))
        return WPMEDIA_NOT_SUPPORTED;
    if (!codecs || !*codecs)
        return WPMEDIA_MAYBE_SUPPORTED;
    for (const char* p = codecs; *p;) {
        while (*p == ' ' || *p == ',' || *p == '"')
            p++;
        const char* end = p;
        while (*end && *end != ',' && *end != '"')
            end++;
        size_t length = end - p;
        while (length && p[length - 1] == ' ')
            length--;
        if (length && !knownCodec(p, length))
            return WPMEDIA_NOT_SUPPORTED;
        p = end;
    }
    return WPMEDIA_SUPPORTED;
}

// MARK: - Events

static void reportMetadata(wpmedia_player* p)
{
    double duration = libvlc_media_player_get_length(p->player) / 1000.0;
    unsigned width = 0, height = 0;
    libvlc_video_get_size(p->player, 0, &width, &height);
    int hasVideo = libvlc_video_get_track_count(p->player) > 0 || width;
    int hasAudio = libvlc_audio_get_track_count(p->player) > 0;
    if (duration < 0)
        duration = 0;
    if (duration == p->duration && width == p->width && height == p->height && hasVideo == p->hasVideo && hasAudio == p->hasAudio)
        return;
    p->duration = duration, p->width = width, p->height = height, p->hasVideo = hasVideo, p->hasAudio = hasAudio;
    if (p->client.metadata_changed)
        p->client.metadata_changed(p->client.context, duration, width, height, hasVideo, hasAudio);
}

static void reportState(wpmedia_player* p, wpmedia_state state)
{
    if (p->client.state_changed)
        p->client.state_changed(p->client.context, state);
}

// Preroll: wpmedia_open starts playing muted, so that the decoder (VideoToolbox
// session) and libVLC's video output (an OpenGL ES view, ~2.5 s to set up on an
// A6) exist before WebCore asks to play. With :start-paused libVLC creates them
// only on play, and the clock runs while the first seconds of video are lost.
// At the first video output (or the first time update, audio only) the player
// pauses back at the start unless asked to play, which also leaves a poster frame.
// libVLC keeps reporting the old position for a while after set_time (it
// reports the target at once, then the old time again, then nothing until the
// demuxer has landed): for 4 s, drop times before the target or further past it
// than the time since the seek allows.
static void seekTo(wpmedia_player* p, double seconds)
{
    debugLog("seek to %.2f", seconds);
    p->seekTarget = seconds;
    p->seekIssued = CFAbsoluteTimeGetCurrent();
    libvlc_media_player_set_time(p->player, (libvlc_time_t)(seconds * 1000));
}

static int isStaleTime(wpmedia_player* p, double seconds)
{
    if (p->seekTarget < 0)
        return 0;
    double elapsed = CFAbsoluteTimeGetCurrent() - p->seekIssued;
    if (elapsed > 4) {
        p->seekTarget = -1;
        return 0;
    }
    return seconds < p->seekTarget - 0.5 || seconds > p->seekTarget + elapsed * p->rate + 1;
}

static void finishPreroll(wpmedia_player* p)
{
    if (p->ready)
        return;
    debugLog("preroll done, pending seek %.2f, wants playing %d", p->pendingSeek, p->wantsPlaying);
    p->ready = 1;
    if (p->pendingSeek >= 0) {
        seekTo(p, p->pendingSeek);
        p->pendingSeek = -1;
    } else if (!p->wantsPlaying)
        seekTo(p, 0);
    libvlc_media_player_set_pause(p->player, !p->wantsPlaying);
    libvlc_audio_set_volume(p->player, p->muted ? 0 : (int)(p->volume * 100));
    reportState(p, p->wantsPlaying ? WPMEDIA_STATE_PLAYING : WPMEDIA_STATE_PAUSED);
}

static void handleEvent(const libvlc_event_t* event, void* data)
{
    wpmedia_player* p = data;
    // libVLC calls back with its event lock held: query the player off this thread.
    switch (event->type) {
    case libvlc_MediaPlayerOpening:
        reportState(p, WPMEDIA_STATE_OPENING);
        break;
    case libvlc_MediaPlayerBuffering: {
        float percent = event->u.media_player_buffering.new_cache;
        if (p->client.buffering)
            p->client.buffering(p->client.context, percent);
        break;
    }
    case libvlc_MediaPlayerPlaying:
        dispatch_async(p->queue, ^{
            reportMetadata(p);
            if (p->ready)
                reportState(p, WPMEDIA_STATE_PLAYING);
        });
        break;
    case libvlc_MediaPlayerPaused:
        dispatch_async(p->queue, ^{
            if (!p->ready)
                return;
            // :play-and-pause stops on the last frame: a pause nobody asked for
            // at the end is the end of the media.
            double time = libvlc_media_player_get_time(p->player) / 1000.0;
            if (p->wantsPlaying && p->duration > 0 && time >= p->duration - 0.5) {
                p->wantsPlaying = 0;
                reportState(p, WPMEDIA_STATE_ENDED);
                return;
            }
            reportState(p, WPMEDIA_STATE_PAUSED);
        });
        break;
    case libvlc_MediaPlayerEndReached:
        reportState(p, WPMEDIA_STATE_ENDED);
        break;
    case libvlc_MediaPlayerEncounteredError:
        reportState(p, WPMEDIA_STATE_ERROR);
        break;
    case libvlc_MediaPlayerTimeChanged: {
        double seconds = event->u.media_player_time_changed.new_time / 1000.0;
        dispatch_async(p->queue, ^{
            debugLog("time %.2f ready %d seekTarget %.2f", seconds, p->ready, p->seekTarget);
            if (!p->ready) {
                // Audio only: no video output will come.
                if (seconds > 0 && !libvlc_video_get_track_count(p->player))
                    finishPreroll(p);
                return;
            }
            if (isStaleTime(p, seconds))
                return;
            if (p->client.time_changed)
                p->client.time_changed(p->client.context, seconds);
        });
        break;
    }
    case libvlc_MediaPlayerLengthChanged:
    case libvlc_MediaPlayerESAdded:
        dispatch_async(p->queue, ^{ reportMetadata(p); });
        break;
    case libvlc_MediaPlayerVout:
        if (event->u.media_player_vout.new_count > 0) {
            // libVLC just added its OpenGL view to the drawable: fit it.
            WPMediaLayer* layer = (__bridge WPMediaLayer*)p->layer;
            dispatch_async(dispatch_get_main_queue(), ^{
                [layer setNeedsLayout];
                [layer layoutIfNeeded];
                if (getenv("WPMEDIA_DEBUG") || !access("/var/webporn/wpmedia-debug", F_OK)) {
                    NSMutableString* dump = [NSMutableString stringWithFormat:@"layer %@ superlayer %@\ndrawable %@ window %@\n", NSStringFromCGRect(layer.frame),
                        layer.superlayer, layer.drawable, layer.drawable.window];
                    for (UIView* view in layer.drawable.subviews)
                        [dump appendFormat:@"  drawable subview %@\n", view];
                    for (UIView* view in [UIApplication sharedApplication].keyWindow.subviews)
                        [dump appendFormat:@"  window subview %@\n", view];
                    [dump writeToFile:@"/var/mobile/Media/webporn/wpmedia.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];
                }
            });
            dispatch_async(p->queue, ^{
                reportMetadata(p);
                finishPreroll(p);
                if (p->client.first_frame)
                    p->client.first_frame(p->client.context);
            });
        }
        break;
    default:
        break;
    }
}

static const libvlc_event_type_t handledEvents[] = { libvlc_MediaPlayerOpening, libvlc_MediaPlayerBuffering,
    libvlc_MediaPlayerPlaying, libvlc_MediaPlayerPaused, libvlc_MediaPlayerEndReached, libvlc_MediaPlayerEncounteredError,
    libvlc_MediaPlayerTimeChanged, libvlc_MediaPlayerLengthChanged, libvlc_MediaPlayerESAdded, libvlc_MediaPlayerVout };

// MARK: - Lifetime

wpmedia_player* wpmedia_create(const wpmedia_client* client)
{
    libvlc_instance_t* instance = sharedInstance();
    if (!instance)
        return NULL;
    wpmedia_player* p = calloc(1, sizeof(*p));
    p->client = *client;
    p->player = libvlc_media_player_new(instance);
    p->queue = dispatch_queue_create("net.webporn.media", DISPATCH_QUEUE_SERIAL);
    p->pendingSeek = -1;
    p->seekTarget = -1;
    p->volume = 1;
    p->rate = 1;
    WPMediaLayer* layer = [WPMediaLayer layer];
    layer.backgroundColor = [UIColor blackColor].CGColor;
    layer.masksToBounds = YES;
    p->layer = (__bridge_retained void*)layer;
    libvlc_event_manager_t* events = libvlc_media_player_event_manager(p->player);
    for (size_t i = 0; i < sizeof(handledEvents) / sizeof(*handledEvents); i++)
        libvlc_event_attach(events, handledEvents[i], handleEvent, p);
    return p;
}

void wpmedia_destroy(wpmedia_player* p)
{
    if (!p)
        return;
    // Detaching waits for a callback in progress; none run after this.
    libvlc_event_manager_t* events = libvlc_media_player_event_manager(p->player);
    for (size_t i = 0; i < sizeof(handledEvents) / sizeof(*handledEvents); i++)
        libvlc_event_detach(events, handledEvents[i], handleEvent, p);
    dispatch_queue_t queue = p->queue;
    libvlc_media_player_t* player = p->player;
    libvlc_media_t* media = p->media;
    WPMediaLayer* layer = (__bridge_transfer WPMediaLayer*)p->layer;
    // Queued metadata work still uses p: free it behind that work.
    dispatch_async(queue, ^{ free(p); });
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        libvlc_media_player_stop(player);
        libvlc_media_player_release(player);
        if (media)
            libvlc_media_release(media);
        dispatch_async(dispatch_get_main_queue(), ^{
            [layer.drawable removeFromSuperview];
            [layer.drawable.layer removeFromSuperlayer];
            layer.drawable = nil;
        });
    });
}

void* wpmedia_layer(wpmedia_player* p)
{
    return p ? p->layer : NULL;
}

// MARK: - Control

// libVLC 3's own mp4 demuxer loses its clock on some files (video-only with an
// edit list: time sticks at 0.25 s, so no timeupdate, no seeking); libavformat's
// does not. "any" falls back to libVLC's demuxers. HLS stays with libVLC's
// adaptive module, which handles it better than libavformat.
static int isMP4Family(const char* url, const char* mimeType)
{
    static const char* const types[] = { "video/mp4", "video/x-m4v", "video/quicktime", "audio/mp4", "audio/x-m4a", "video/3gpp", "audio/3gpp", NULL };
    if (mimeType && *mimeType)
        return caseInsensitiveIn(mimeType, types);
    const char* path = strrchr(url, '/');
    const char* dot = path ? strrchr(path, '.') : NULL;
    if (!dot)
        return 0;
    static const char* const extensions[] = { ".mp4", ".m4v", ".mov", ".m4a", ".3gp", NULL };
    for (const char* const* extension = extensions; *extension; extension++) {
        size_t length = strlen(*extension);
        if (!strncasecmp(dot, *extension, length) && (!dot[length] || dot[length] == '?' || dot[length] == '#'))
            return 1;
    }
    return 0;
}

void wpmedia_open(wpmedia_player* p, const char* url, const char* mimeType, const char* userAgent, const char* referrer)
{
    libvlc_media_t* media = libvlc_media_new_location(sharedInstance(), url);
    if (!media) {
        reportState(p, WPMEDIA_STATE_ERROR);
        return;
    }
    // Pause on the last frame instead of stopping: a stopped input closes the video
    // output, and replaying or seeking back would set it up again (~2.5 s).
    libvlc_media_add_option(media, ":play-and-pause");
    if (isMP4Family(url, mimeType))
        libvlc_media_add_option(media, ":demux=avformat,any");
    if (userAgent && *userAgent) {
        char option[1024];
        snprintf(option, sizeof(option), ":http-user-agent=%s", userAgent);
        libvlc_media_add_option(media, option);
    }
    if (referrer && *referrer) {
        char option[2048];
        snprintf(option, sizeof(option), ":http-referrer=%s", referrer);
        libvlc_media_add_option(media, option);
    }
    WPMediaLayer* layer = (__bridge WPMediaLayer*)p->layer;
    libvlc_media_player_t* player = p->player;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView* drawable = [[UIView alloc] initWithFrame:layer.bounds];
        drawable.backgroundColor = [UIColor blackColor];
        drawable.userInteractionEnabled = NO;
        drawable.clipsToBounds = YES;
        layer.drawable = drawable;
        [layer addSublayer:drawable.layer];
        [layer setNeedsLayout];
        dispatch_async(p->queue, ^{
            libvlc_media_player_set_nsobject(player, (__bridge void*)drawable);
            libvlc_media_player_set_media(player, media);
            p->media = media;
            libvlc_audio_set_volume(player, 0); // until finishPreroll
            libvlc_media_player_set_rate(player, p->rate);
            libvlc_media_player_play(player);
        });
    });
}

void wpmedia_play(wpmedia_player* p)
{
    dispatch_async(p->queue, ^{
        p->wantsPlaying = 1;
        if (p->ready)
            libvlc_media_player_set_pause(p->player, 0);
    });
}

void wpmedia_pause(wpmedia_player* p)
{
    dispatch_async(p->queue, ^{
        p->wantsPlaying = 0;
        if (p->ready)
            libvlc_media_player_set_pause(p->player, 1);
    });
}

void wpmedia_seek(wpmedia_player* p, double seconds)
{
    dispatch_async(p->queue, ^{
        debugLog("wpmedia_seek %.2f ready %d", seconds, p->ready);
        if (p->ready)
            seekTo(p, seconds);
        else
            p->pendingSeek = seconds;
    });
}

double wpmedia_time(wpmedia_player* p)
{
    if (!p->ready)
        return 0;
    libvlc_time_t time = libvlc_media_player_get_time(p->player);
    return time > 0 ? time / 1000.0 : 0;
}

void wpmedia_set_rate(wpmedia_player* p, float rate)
{
    dispatch_async(p->queue, ^{
        p->rate = rate;
        libvlc_media_player_set_rate(p->player, rate);
    });
}

void wpmedia_set_volume(wpmedia_player* p, float volume)
{
    dispatch_async(p->queue, ^{
        p->volume = volume;
        if (!p->muted && p->ready)
            libvlc_audio_set_volume(p->player, (int)(volume * 100));
    });
}

void wpmedia_set_muted(wpmedia_player* p, int muted)
{
    dispatch_async(p->queue, ^{
        p->muted = muted;
        if (p->ready)
            libvlc_audio_set_volume(p->player, muted ? 0 : (int)(p->volume * 100));
    });
}
