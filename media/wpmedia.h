// wpmedia: the C ABI between WebCore's MediaPlayerPrivateWebPorn and
// libWebPornMedia.dylib (libVLC). WebCore dlopens the library, so no C++ crosses
// the boundary and the LGPL code stays in its own image. A copy of this header
// lives in Source/WebCore/platform/graphics/webporn/; keep them identical.
//
// Threading: every function may be called from any thread. Client callbacks
// arrive on libVLC's event thread (or the main thread) and must not call back
// into the player synchronously.

#ifndef WPMEDIA_H
#define WPMEDIA_H

#ifdef __cplusplus
extern "C" {
#endif

#define WPMEDIA_ABI_VERSION 1

typedef struct wpmedia_player wpmedia_player;

typedef enum {
    WPMEDIA_STATE_IDLE,
    WPMEDIA_STATE_OPENING,
    WPMEDIA_STATE_BUFFERING,
    WPMEDIA_STATE_PLAYING,
    WPMEDIA_STATE_PAUSED,
    WPMEDIA_STATE_ENDED,
    WPMEDIA_STATE_ERROR,
} wpmedia_state;

typedef enum {
    WPMEDIA_NOT_SUPPORTED,
    WPMEDIA_MAYBE_SUPPORTED,
    WPMEDIA_SUPPORTED,
} wpmedia_support;

typedef struct {
    void* context;
    void (*state_changed)(void* context, wpmedia_state);
    // Metadata is known: duration (seconds, 0 when live / unknown), video size
    // (0 x 0 for audio only), whether there are video / audio tracks.
    void (*metadata_changed)(void* context, double duration, unsigned width, unsigned height, int has_video, int has_audio);
    // Current time moved (playback or a finished seek).
    void (*time_changed)(void* context, double seconds);
    // Network cache fill, 0-100.
    void (*buffering)(void* context, float percent);
    // A first video frame is on screen.
    void (*first_frame)(void* context);
} wpmedia_client;

int wpmedia_abi_version(void);

// container: MIME type without parameters ("video/mp4"); codecs: the codecs
// parameter or NULL / "".
wpmedia_support wpmedia_supports(const char* container, const char* codecs);

// The client is copied; its callbacks run until wpmedia_destroy returns.
wpmedia_player* wpmedia_create(const wpmedia_client*);
void wpmedia_destroy(wpmedia_player*);

// A CALayer (owned by the player) that shows the video scaled to fit, and
// follows its own bounds. Valid until wpmedia_destroy.
void* wpmedia_layer(wpmedia_player*);

// Opens the URL paused: metadata arrives without playing. mime_type (the
// element's or the response's, without parameters), user_agent and referrer may
// be NULL.
void wpmedia_open(wpmedia_player*, const char* url, const char* mime_type, const char* user_agent, const char* referrer);
void wpmedia_play(wpmedia_player*);
void wpmedia_pause(wpmedia_player*);
void wpmedia_seek(wpmedia_player*, double seconds);
double wpmedia_time(wpmedia_player*);
void wpmedia_set_rate(wpmedia_player*, float rate);
void wpmedia_set_volume(wpmedia_player*, float volume); // 0-1
void wpmedia_set_muted(wpmedia_player*, int muted);

#ifdef __cplusplus
}
#endif

#endif
