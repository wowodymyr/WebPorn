// Headless smoke test of the WebPorn engine: create our WebKitLegacy WebView (a
// WAKView, no UIApplication needed), load HTML, let it run, evaluate JS.
// The system WebKitLegacy is in the process too (UIKit links it), so classes are
// taken from our image with dlsym instead of by name.
//   webview-smoke [--web-thread] [html-file] [--png out.png]
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>

#define MSG(ret, ...) ((ret (*)(id, SEL, ##__VA_ARGS__))objc_msgSend)

static const char* defaultHTML =
    "<!doctype html><meta charset=utf-8><title>t</title><style>"
    "body{font:16px -apple-system,Helvetica;margin:8px}"
    "#x{display:grid;grid-template-columns:100px 50px;gap:4px}#x>*{background:#e33;color:#fff;padding:2px}"
    ".g{height:40px;margin:6px 0;border-radius:20px 4px 20px 4px;background:linear-gradient(90deg,#08f,#f80)}"
    ".c{width:80px;height:80px;border-radius:50%;background:conic-gradient(red,yellow,lime,cyan,blue,magenta,red);display:inline-block}"
    ".s{display:inline-block;width:80px;height:80px;margin-left:16px;background:#fff;box-shadow:0 4px 12px rgba(0,0,0,.5);border:2px dashed #555}"
    "p{margin:4px 0}.mono{font-family:monospace}.serif{font-family:serif;font-size:20px}"
    "</style><div id=x><span>grid a</span><span>b</span></div>"
    "<div class=g></div><div class=c></div><div class=s></div>"
    "<p>Latin: The quick brown fox — fi fl ffi</p><p>Кириллица: Съешь же ещё этих мягких булок</p>"
    "<p>Emoji: \xF0\x9F\x98\x80\xF0\x9F\x8D\x95\xE2\x9D\xA4\xEF\xB8\x8F</p><p dir=rtl>العربية: مرحبا بالعالم</p>"
    "<p class=mono>monospace 0123456789</p><p class=serif>Serif Italic <i>text</i> <b>bold</b></p>"
    "<script>document.title = 'loaded:' + (6 * 7);</script>";

static const char* probeJS =
    "(() => { try { const r = document.getElementById('x').getBoundingClientRect();"
    " const s = document.querySelector('#x>span').getBoundingClientRect();"
    " return [document.title, navigator.userAgent, 'grid ' + r.width + 'x' + r.height + ' first ' + s.width + 'x' + s.height,"
    " 'css.supports(has) ' + CSS.supports('selector(:has(a))'), 'at ' + [1,2,3].at(-1),"
    " 'structuredClone ' + typeof structuredClone, 'intl ' + new Intl.DateTimeFormat('ru', {timeZone: 'UTC'}).format(0),"
    " 'cookie ' + (document.cookie = 'a=1', document.cookie)].join('\\n'); }"
    " catch (e) { return 'exception: ' + e; } })()";

static id nsString(const char* s) { return (__bridge id)CFStringCreateWithCString(NULL, s, kCFStringEncodingUTF8); }

int main(int argc, char** argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    const char* pngPath = NULL;
    if (argc > 2 && !strcmp(argv[argc - 2], "--png")) {
        pngPath = argv[argc - 1];
        argc -= 2;
    }
    int webThread = argc > 1 && !strcmp(argv[1], "--web-thread");
    const char* htmlPath = argc > 1 + webThread ? argv[1 + webThread] : NULL;

    void* webKit = dlopen("/var/webporn/lib/WebKitLegacy.framework/WebKitLegacy", RTLD_NOW | RTLD_LOCAL);
    if (!webKit) {
        printf("dlopen: %s\n", dlerror());
        return 1;
    }
    Class WebView = (__bridge Class)dlsym(webKit, "OBJC_CLASS_$_WebView");
    void (*webKitInitialize)(void) = dlsym(webKit, "WebKitInitialize");
    void (*webThreadLockReal)(void) = dlsym(webKit, "WebThreadLock");
    bool (*webThreadIsEnabled)(void) = dlsym(webKit, "WebThreadIsEnabled");
    printf("WebView %p (system %p), WebKitInitialize %p\n", WebView, objc_getClass("WebView"), webKitInitialize);

    id pool = MSG(id)(MSG(id)((id)objc_getClass("NSAutoreleasePool"), sel_registerName("alloc")), sel_registerName("init"));
    if (webThread)
        MSG(void)((id)WebView, sel_registerName("enableWebThread"));
    webKitInitialize();
    printf("initialized (web thread requested %s, running %d)\n", webThread ? "yes" : "no", webThreadIsEnabled());
    // Like UIWebView: hold the web lock on the main thread whenever WebCore is touched;
    // it is released at the end of each run loop iteration.
    void (*webThreadLock)(void) = webThreadLockReal;
    webThread = 1;
    webThreadLock();

    id webView = MSG(id, CGRect)(MSG(id)((id)WebView, sel_registerName("alloc")), sel_registerName("initWithFrame:"), CGRectMake(0, 0, 320, 480));
    printf("webView %p\n", webView);
    id frame = MSG(id)(webView, sel_registerName("mainFrame"));

    id html;
    if (htmlPath) {
        FILE* f = fopen(htmlPath, "rb");
        static char buffer[1 << 20];
        size_t n = f ? fread(buffer, 1, sizeof(buffer) - 1, f) : 0;
        buffer[n] = 0;
        html = nsString(buffer);
    } else
        html = nsString(defaultHTML);
    id baseURL = MSG(id, id)((id)objc_getClass("NSURL"), sel_registerName("URLWithString:"), nsString("http://webporn.test/"));
    if (webThread && webThreadLock)
        webThreadLock();
    MSG(void, id, id)(frame, sel_registerName("loadHTMLString:baseURL:"), html, baseURL);
    printf("load started\n");

    for (int i = 0; i < 100; i++) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
        if (webThread && webThreadLock)
            webThreadLock();
        if (!MSG(BOOL)(webView, sel_registerName("isLoading")) && i > 4)
            break;
    }

    if (webThread && webThreadLock)
        webThreadLock();
    id result = MSG(id, id)(webView, sel_registerName("stringByEvaluatingJavaScriptFromString:"), nsString(probeJS));
    printf("JS result:\n%s\n", result ? MSG(const char*)(result, sel_registerName("UTF8String")) : "(nil)");

    if (pngPath) {
        void (*setCurrentContext)(CGContextRef) = dlsym(webKit, "WKSetCurrentGraphicsContext");
        const size_t scale = 2, width = 320, height = 480;
        CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, width * scale, height * scale, 8, 0, rgb, kCGImageAlphaPremultipliedLast);
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, width * scale, height * scale));
        // WebCore paints top-down.
        CGContextTranslateCTM(context, 0, height * scale);
        CGContextScaleCTM(context, scale, -(CGFloat)scale);
        setCurrentContext(context);
        MSG(void, CGRect, BOOL)(frame, sel_registerName("_drawRect:contentsOnly:"), CGRectMake(0, 0, width, height), NO);
        setCurrentContext(NULL);
        CGImageRef image = CGBitmapContextCreateImage(context);
        CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)pngPath, strlen(pngPath), false);
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
        CGImageDestinationAddImage(destination, image, NULL);
        printf("png %s: %s\n", pngPath, CGImageDestinationFinalize(destination) ? "written" : "failed");
    }
    MSG(void)(pool, sel_registerName("drain"));
    return 0;
}
