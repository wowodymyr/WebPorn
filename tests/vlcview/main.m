// VLCView: play /var/mobile/Media/webporn/vlc-url.txt with libvlc's own video
// output (VideoToolbox + OpenGL ES into a UIView) and write libvlc's stats after
// N seconds (vlc-seconds.txt, default 15) to vlc-result.txt. `uiopen vlcview:`.
// The frame is vlc-frame.txt ("x y w h" in points; default full width 16:9).
// vlc-mode.txt "wpmedia": go through libWebPornMedia instead (its CALayer in the
// view's layer tree, opened paused, play after 2 s, seek to 5 s after 6 s),
// logging its callbacks into vlc-result.txt.
#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <vlc/vlc.h>
#include "../../media/wpmedia.h"

static NSString* const kDir = @"/var/mobile/Media/webporn";

@interface VVAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow* window;
@end

@implementation VVAppDelegate {
    libvlc_instance_t* _vlc;
    libvlc_media_t* _media;
    libvlc_media_player_t* _player;
    CFAbsoluteTime _start;
}

static NSString* readSetting(NSString* name)
{
    NSString* value = [NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [UIViewController new];
    self.window.backgroundColor = [UIColor darkGrayColor];
    CGFloat width = self.window.bounds.size.width;
    CGRect frame = CGRectMake(0, 40, width, width * 9 / 16);
    NSArray* parts = [readSetting(@"vlc-frame.txt") componentsSeparatedByString:@" "];
    if (parts.count == 4)
        frame = CGRectMake([parts[0] doubleValue], [parts[1] doubleValue], [parts[2] doubleValue], [parts[3] doubleValue]);
    UIView* drawable = [[UIView alloc] initWithFrame:frame];
    if ([readSetting(@"vlc-mode.txt") isEqualToString:@"wpmedia"])
        drawable.hidden = YES;
    drawable.backgroundColor = [UIColor blackColor];
    [self.window.rootViewController.view addSubview:drawable];
    [self.window makeKeyAndVisible];

    NSString* url = readSetting(@"vlc-url.txt");
    if ([readSetting(@"vlc-mode.txt") isEqualToString:@"wpmedia"]) {
        [self startWPMedia:url frame:frame];
        return YES;
    }
    _vlc = libvlc_new(0, NULL);
    _media = libvlc_media_new_location(_vlc, url.UTF8String);
    _player = libvlc_media_player_new_from_media(_media);
    libvlc_media_player_set_nsobject(_player, (__bridge void*)drawable);
    _start = CFAbsoluteTimeGetCurrent();
    libvlc_media_player_play(_player);

    double seconds = readSetting(@"vlc-seconds.txt").doubleValue ?: 15;
    [self performSelector:@selector(report) withObject:nil afterDelay:seconds];
    return YES;
}

static NSMutableString* events;
static CFAbsoluteTime eventStart;

static void logEvent(NSString* text)
{
    @synchronized (events) {
        [events appendFormat:@"%6.2f %@\n", CFAbsoluteTimeGetCurrent() - eventStart, text];
        [events writeToFile:[kDir stringByAppendingPathComponent:@"vlc-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void onState(void* context, wpmedia_state state) { logEvent([NSString stringWithFormat:@"state %d", state]); }
static void onMetadata(void* context, double duration, unsigned width, unsigned height, int hasVideo, int hasAudio)
{
    logEvent([NSString stringWithFormat:@"metadata %.2f s %ux%u video %d audio %d", duration, width, height, hasVideo, hasAudio]);
}
static void onTime(void* context, double seconds)
{
    static int count;
    if (!(count++ % 8))
        logEvent([NSString stringWithFormat:@"time %.2f", seconds]);
}
static void onBuffering(void* context, float percent) { if (percent >= 100) logEvent(@"buffered 100"); }
static void onFirstFrame(void* context) { logEvent(@"first frame"); }

- (void)startWPMedia:(NSString*)url frame:(CGRect)frame
{
    events = [NSMutableString string];
    eventStart = CFAbsoluteTimeGetCurrent();
    void* library = dlopen("/var/webporn/lib/libWebPornMedia.dylib", RTLD_NOW);
    if (!library) {
        logEvent([NSString stringWithFormat:@"dlopen: %s", dlerror()]);
        return;
    }
    wpmedia_player* (*create)(const wpmedia_client*) = dlsym(library, "wpmedia_create");
    void* (*layerOf)(wpmedia_player*) = dlsym(library, "wpmedia_layer");
    void (*open)(wpmedia_player*, const char*, const char*, const char*, const char*) = dlsym(library, "wpmedia_open");
    void (*play)(wpmedia_player*) = dlsym(library, "wpmedia_play");
    void (*seek)(wpmedia_player*, double) = dlsym(library, "wpmedia_seek");
    wpmedia_support (*supports)(const char*, const char*) = dlsym(library, "wpmedia_supports");
    logEvent([NSString stringWithFormat:@"supports mp4/avc1 %d, webm/vp9 %d, webm/av01 %d, video/x-foo %d", supports("video/mp4", "avc1.42E01E, mp4a.40.2"),
        supports("video/webm", "vp09.00.10.08"), supports("video/webm", "av01.0.05M.08"), supports("video/x-foo", NULL)]);
    wpmedia_client client = { NULL, onState, onMetadata, onTime, onBuffering, onFirstFrame };
    wpmedia_player* player = create(&client);
    CALayer* layer = (__bridge CALayer*)layerOf(player);
    layer.frame = frame;
    [self.window.rootViewController.view.layer addSublayer:layer];
    open(player, url.UTF8String, NULL, "WPTest", NULL);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ logEvent(@"-> play"); play(player); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ logEvent(@"-> seek 5"); seek(player, 5); });
    // Snapshot cost (libvlc_video_take_snapshot through the library's player is not
    // exported, so time it on a second libvlc player opened on the same URL).
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
        libvlc_media_player_t* (*rawPlayer)(wpmedia_player*) = dlsym(library, "wpmedia_debug_vlc_player");
        if (!rawPlayer) { logEvent(@"no wpmedia_debug_vlc_player"); return; }
        dispatch_sync(dispatch_get_main_queue(), ^{
            CALayer* host = (__bridge CALayer*)layerOf(player);
            UIView* drawable = [host valueForKey:@"drawable"];
            for (int i = 0; i < 3; i++) {
                CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
                CGSize size = drawable.bounds.size;
                UIGraphicsBeginImageContextWithOptions(size, YES, 1);
                BOOL ok = [drawable drawViewHierarchyInRect:drawable.bounds afterScreenUpdates:NO];
                UIImage* image = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                CGImageRef cg = image.CGImage;
                // Mean of the first row's bytes, to tell black from a real frame.
                CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cg));
                const UInt8* bytes = CFDataGetBytePtr(data);
                unsigned long sum = 0, n = CFDataGetLength(data);
                for (unsigned long k = 0; k < n; k += 97) sum += bytes[k];
                CFRelease(data);
                logEvent([NSString stringWithFormat:@"drawViewHierarchy %d: ok %d, %.0f ms, %zux%zu, mean %.1f", i, ok,
                    (CFAbsoluteTimeGetCurrent() - start) * 1000, CGImageGetWidth(cg), CGImageGetHeight(cg), (double)sum / (n / 97)]);
            }
        });
        for (int i = 0; i < 3; i++) {
            NSString* path = [NSString stringWithFormat:@"%@/snap%d.png", kDir, i];
            CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
            int rc = libvlc_video_take_snapshot(rawPlayer(player), 0, path.UTF8String, 320, 0);
            NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            logEvent([NSString stringWithFormat:@"snapshot %d: rc %d, %.0f ms, %llu bytes", i, rc, (CFAbsoluteTimeGetCurrent() - start) * 1000, attributes.fileSize]);
        }
    });
}

- (void)report
{
    if (events)
        return;
    libvlc_media_stats_t stats = { };
    libvlc_media_get_stats(_media, &stats);
    unsigned width = 0, height = 0;
    libvlc_video_get_size(_player, 0, &width, &height);
    NSString* result = [NSString stringWithFormat:@"url %@\nsource %ux%u, position %lld ms of %lld, state %d\nelapsed %.1f s: decoded %d, displayed %d, lost %d, audio decoded %d, played %d, lost %d\n",
        readSetting(@"vlc-url.txt"), width, height, (long long)libvlc_media_player_get_time(_player), (long long)libvlc_media_player_get_length(_player),
        libvlc_media_player_get_state(_player), CFAbsoluteTimeGetCurrent() - _start, stats.i_decoded_video, stats.i_displayed_pictures,
        stats.i_lost_pictures, stats.i_decoded_audio, stats.i_played_abuffers, stats.i_lost_abuffers];
    [result writeToFile:[kDir stringByAppendingPathComponent:@"vlc-result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@end

int main(int argc, char* argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([VVAppDelegate class]));
    }
}
