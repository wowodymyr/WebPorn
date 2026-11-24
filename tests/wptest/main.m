// WPTest: a UIWebView test app. Loads /var/mobile/Media/webporn/url.txt (a URL)
// or test.html from that directory, then writes result.txt (JS probes) and
// screenshot.png there (capture-delay.txt seconds after the load, default 2).
// Launch with `uiopen wptest:`.
#import <UIKit/UIKit.h>

#ifdef WP_SANDBOXED
// WPBox: the same app installed as an App Store app would be (container, sandbox,
// no entitlements); its files are in its Documents directory.
#define kDir [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]
#else
static NSString *const kDir = @"/var/mobile/Media/webporn";
#endif

static NSString *const kProbe =
    @"(() => { try { return [navigator.userAgent, document.title,"
    @" 'grid ' + CSS.supports('display:grid') + ' has ' + CSS.supports('selector(:has(a))'),"
    @" 'at ' + typeof [].at + ' structuredClone ' + typeof structuredClone,"
    @" 'size ' + innerWidth + 'x' + innerHeight + ' dpr ' + devicePixelRatio].join('\\n'); }"
    @" catch (e) { return 'exception: ' + e; } })() || 'no ES6 arrow functions: old engine'";

@interface WPAppDelegate : UIResponder <UIApplicationDelegate, UIWebViewDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIWebView *webView;
@property (nonatomic) BOOL captured;
@property (nonatomic) BOOL repeating;
@end

@implementation WPAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UIViewController *controller = [UIViewController new];
    self.webView = [[UIWebView alloc] initWithFrame:controller.view.bounds];
    self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.webView.delegate = self;
    // Media tests (tests/media): play inline and without a tap, like a desktop page.
    self.webView.allowsInlineMediaPlayback = YES;
    self.webView.mediaPlaybackRequiresUserAction = NO;
    [controller.view addSubview:self.webView];
    self.window.rootViewController = controller;
    [self.window makeKeyAndVisible];

    [[NSFileManager defaultManager] createDirectoryAtPath:kDir withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[kDir stringByAppendingPathComponent:@"result.txt"] error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:[kDir stringByAppendingPathComponent:@"error.txt"] error:nil];
    NSString *url = [[NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"url.txt"] encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *html = [NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"test.html"] encoding:NSUTF8StringEncoding error:nil];
    if (url.length)
        [self.webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
    else
        [self.webView loadHTMLString:html ?: @"<h1>WPTest</h1><p>no test.html</p>" baseURL:[NSURL URLWithString:@"http://webporn.test/"]];
    NSLog(@"WPTest: loading %@", url.length ? url : @"test.html");
    // Pages that never finish loading (video sites) are probed anyway.
    [self performSelector:@selector(captureIfNeeded) withObject:nil afterDelay:20];
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (webView.isLoading)
        return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(capture) object:nil];
    // capture-delay.txt: seconds to wait after the load (media tests need longer).
    double delay = [[NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"capture-delay.txt"] encoding:NSUTF8StringEncoding error:nil] doubleValue];
    [self performSelector:@selector(capture) withObject:nil afterDelay:delay > 0 ? delay : 2];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    NSLog(@"WPTest: load failed: %@", error);
    [[NSString stringWithFormat:@"%@\n", error] writeToFile:[kDir stringByAppendingPathComponent:@"error.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self performSelector:@selector(capture) withObject:nil afterDelay:1];
}

- (void)captureIfNeeded
{
    if (!self.captured)
        [self capture];
}

- (void)capture
{
    self.captured = YES;
    // probe.js, when present, replaces the built-in probe (any expression yielding a string).
    NSString *probe = [NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"probe.js"] encoding:NSUTF8StringEncoding error:nil] ?: kProbe;
    NSString *result = [self.webView stringByEvaluatingJavaScriptFromString:probe];
    // prefs.txt: preference keys (one per line) to report from the WebView's WebPreferences.
    NSString *prefKeys = [NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"prefs.txt"] encoding:NSUTF8StringEncoding error:nil];
    if (prefKeys.length) {
        id documentView = [self.webView respondsToSelector:@selector(_documentView)] ? [self.webView performSelector:@selector(_documentView)] : nil;
        id preferences = [[documentView performSelector:@selector(webView)] performSelector:@selector(preferences)];
        NSMutableString *report = [NSMutableString stringWithFormat:@"%@\n# prefs %@ (%@)\n", result, preferences, [preferences performSelector:@selector(identifier)]];
        for (NSString *key in [prefKeys componentsSeparatedByString:@"\n"]) {
            if (key.length)
                [report appendFormat:@"%@ = %@ (defaults %@)\n", key, [preferences performSelector:@selector(_valueForKey:) withObject:key], [[NSUserDefaults standardUserDefaults] objectForKey:key]];
        }
        result = report;
    }
    [result writeToFile:[kDir stringByAppendingPathComponent:@"result.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIGraphicsBeginImageContextWithOptions(self.window.bounds.size, YES, 0);
    [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [UIImagePNGRepresentation(image) writeToFile:[kDir stringByAppendingPathComponent:@"screenshot.png"] atomically:YES];
    NSLog(@"WPTest: captured: %@", result);
    // capture-repeat.txt: probe again every that many seconds, appending to results.txt.
    double repeat = [[NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"capture-repeat.txt"] encoding:NSUTF8StringEncoding error:nil] doubleValue];
    if (repeat > 0 && !self.repeating) {
        self.repeating = YES;
        [self performSelector:@selector(probeAgain) withObject:nil afterDelay:repeat];
    }
}

- (void)probeAgain
{
    NSString *probe = [NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"probe.js"] encoding:NSUTF8StringEncoding error:nil] ?: kProbe;
    NSString *line = [NSString stringWithFormat:@"%.1f %@\n", [[NSProcessInfo processInfo] systemUptime], [self.webView stringByEvaluatingJavaScriptFromString:probe]];
    NSString *path = [kDir stringByAppendingPathComponent:@"results.txt"];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
    } else {
        [handle seekToEndOfFile];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [handle closeFile];
    }
    double repeat = [[NSString stringWithContentsOfFile:[kDir stringByAppendingPathComponent:@"capture-repeat.txt"] encoding:NSUTF8StringEncoding error:nil] doubleValue];
    if (repeat > 0)
        [self performSelector:@selector(probeAgain) withObject:nil afterDelay:repeat];
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([WPAppDelegate class]));
    }
}
