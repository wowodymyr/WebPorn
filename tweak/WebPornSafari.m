// WebPornSafari: run MobileSafari on WebKitLegacy, so that WebPornSwap can put
// the new engine under it.
//
// iOS 8 Safari still carries its WebKit1 implementation (BrowserControllerWK1,
// TabDocumentWK1, LoadingControllerWK1, HistoryWK1, ReaderContextWK1), chosen
// by the UseLegacyWebKit default. It has rotted: it sends selectors that no
// class implements any more (-_updateReaderBackgroundViewFrame at launch).
//  1. UseLegacyWebKit = YES in the NSUserDefaults argument domain (not persisted).
//  2. Safari's own classes answer selectors nobody implements with nil / 0
//     instead of throwing, and each one is logged once, so the rot shows up in
//     one run. This goes through -methodSignatureForSelector: /
//     -forwardInvocation:, which -respondsToSelector: does not consult, so
//     optional-method checks keep their answers.
//  3. `notifypost net.webporn.screenshot` writes the app's screen to
//     /var/mobile/Media/webporn/safari.png (no screenshot tool on the device).
// Log: /var/mobile/Media/webporn/safari.log

#import <UIKit/UIKit.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdio.h>

#define LOG_PATH "/var/mobile/Media/webporn/safari.log"

static FILE* logFile;
static NSMutableSet* loggedSelectors;

static void logf_(const char* format, ...) __attribute__((format(printf, 1, 2)));
static void logf_(const char* format, ...)
{
    if (!logFile)
        return;
    static CFAbsoluteTime start;
    if (!start)
        start = CFAbsoluteTimeGetCurrent();
    fprintf(logFile, "%7.3f ", CFAbsoluteTimeGetCurrent() - start);
    va_list args;
    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);
    fflush(logFile);
}

// MARK: - Defaults

static void useLegacyWebKit(void)
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* arguments = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary dictionary];
    arguments[@"UseLegacyWebKit"] = @YES;
    [defaults removeVolatileDomainForName:NSArgumentDomain];
    [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
}

// MARK: - Missing selectors

static NSMethodSignature* (*originalMethodSignature)(id, SEL, SEL);
static void (*originalForwardInvocation)(id, SEL, NSInvocation*);
static const struct mach_header* safariHeader;

static bool isSafariClass(Class cls)
{
    Dl_info info;
    return dladdr((__bridge void*)cls, &info) && info.dli_fbase == safariHeader;
}

static NSMethodSignature* nilReturningSignature(SEL selector)
{
    const char* name = sel_getName(selector);
    char types[64] = "@@:";
    size_t length = 3;
    for (const char* p = name; *p && length < sizeof(types) - 1; p++) {
        if (*p == ':')
            types[length++] = '@';
    }
    types[length] = 0;
    return [NSMethodSignature signatureWithObjCTypes:types];
}

static NSMethodSignature* safariMethodSignature(id self, SEL _cmd, SEL selector)
{
    NSMethodSignature* signature = originalMethodSignature(self, _cmd, selector);
    if (signature || !isSafariClass(object_getClass(self)))
        return signature;
    return nilReturningSignature(selector);
}

static NSMutableSet* tracedSelectors;

static SEL tracedOriginal(SEL selector)
{
    return sel_registerName([@"wptrace_" stringByAppendingString:NSStringFromSelector(selector)].UTF8String);
}

static void safariForwardInvocation(id self, SEL _cmd, NSInvocation* invocation)
{
    if (tracedSelectors && [tracedSelectors containsObject:NSStringFromSelector(invocation.selector)]
        && class_respondsToSelector(object_getClass(self), tracedOriginal(invocation.selector))) {
        const char* name = sel_getName(invocation.selector);
        logf_("> %s %s\n", [NSThread isMainThread] ? "main" : "web ", name);
        invocation.selector = tracedOriginal(invocation.selector);
        [invocation invoke];
        logf_("< %s\n", name);
        return;
    }
    if (!isSafariClass(object_getClass(self))) {
        originalForwardInvocation(self, _cmd, invocation);
        return;
    }
    NSString* key = [NSString stringWithFormat:@"%s %s", class_getName(object_getClass(self)), sel_getName(invocation.selector)];
    @synchronized (loggedSelectors) {
        if (![loggedSelectors containsObject:key]) {
            [loggedSelectors addObject:key];
            logf_("missing: -[%s]\n", key.UTF8String);
        }
    }
    id result = nil;
    [invocation setReturnValue:&result];
}

static void installMissingSelectorFallback(void)
{
    loggedSelectors = [[NSMutableSet alloc] init]; // no ARC: keep it
    Method signature = class_getInstanceMethod([NSObject class], @selector(methodSignatureForSelector:));
    Method forward = class_getInstanceMethod([NSObject class], @selector(forwardInvocation:));
    originalMethodSignature = (void*)method_setImplementation(signature, (IMP)safariMethodSignature);
    originalForwardInvocation = (void*)method_setImplementation(forward, (IMP)safariForwardInvocation);
}

// MARK: - Delegate trace

// /var/webporn/safari-trace present: log entry and exit of every WebView delegate
// method of the WK1 controllers (any signature: the method is routed through
// _objc_msgForward to safariForwardInvocation, which calls the original).
static void traceDelegateMethods(void)
{
    if (access("/var/webporn/safari-trace", F_OK))
        return;
    tracedSelectors = [[NSMutableSet alloc] init];
    for (NSString* className in @[ @"TabDocumentWK1", @"BrowserControllerWK1", @"LoadingControllerWK1" ]) {
        Class cls = objc_getClass(className.UTF8String);
        unsigned count = 0;
        Method* methods = class_copyMethodList(cls, &count);
        for (unsigned i = 0; i < count; i++) {
            SEL selector = method_getName(methods[i]);
            const char* name = sel_getName(selector);
            const char* types = method_getTypeEncoding(methods[i]);
            if (strncmp(name, "webView:", 8) && strncmp(name, "webThreadWebView", 16) && strncmp(name, "_webView", 8))
                continue;
            if (types[0] == '{') // would need _objc_msgForward_stret
                continue;
            class_addMethod(cls, tracedOriginal(selector), method_getImplementation(methods[i]), types);
            method_setImplementation(methods[i], _objc_msgForward);
            [tracedSelectors addObject:NSStringFromSelector(selector)];
        }
        free(methods);
    }
    logf_("tracing %lu delegate methods\n", (unsigned long)tracedSelectors.count);
}

// MARK: - Engine call trace

static void (*originalSetSchedulerSuspended)(id, SEL, BOOL);
static int schedulerSuspendBalance;

static void traceSetSchedulerSuspended(id self, SEL _cmd, BOOL suspend)
{
    schedulerSuspendBalance += suspend ? 1 : -1;
    logf_("_setResourceLoadSchedulerSuspended:%d (balance %d)\n", suspend, schedulerSuspendBalance);
    originalSetSchedulerSuspended(self, _cmd, suspend);
}

// After launch, so that WebView is the new engine's class (WebPornSwap runs after us).
static void traceEngineCalls(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        Method method = class_getInstanceMethod(objc_getClass("WebView"), sel_registerName("_setResourceLoadSchedulerSuspended:"));
        if (method)
            originalSetSchedulerSuspended = (void*)method_setImplementation(method, (IMP)traceSetSchedulerSuspended);
    });
}

// MARK: - Authentication trace

static BOOL (*originalCanAuthenticate)(id, SEL, id, id, NSURLProtectionSpace*, id);
static void (*originalDidReceiveChallenge)(id, SEL, id, id, NSURLAuthenticationChallenge*, id);

static BOOL traceCanAuthenticate(id self, SEL _cmd, id webView, id resource, NSURLProtectionSpace* space, id dataSource)
{
    BOOL result = originalCanAuthenticate(self, _cmd, webView, resource, space, dataSource);
    logf_("canAuthenticateAgainstProtectionSpace %s %s -> %d\n", space.host.UTF8String, space.authenticationMethod.UTF8String, result);
    return result;
}

static void traceDidReceiveChallenge(id self, SEL _cmd, id webView, id resource, NSURLAuthenticationChallenge* challenge, id dataSource)
{
    logf_("didReceiveAuthenticationChallenge %s %s sender %s\n", challenge.protectionSpace.host.UTF8String,
        challenge.protectionSpace.authenticationMethod.UTF8String, class_getName(object_getClass(challenge.sender)));
    originalDidReceiveChallenge(self, _cmd, webView, resource, challenge, dataSource);
    logf_("didReceiveAuthenticationChallenge returned\n");
}

static void (*originalDidFinishLoading)(id, SEL, id, id, id);
static void (*originalDidFailLoading)(id, SEL, id, id, NSError*, id);
static id (*originalWillSendRequest)(id, SEL, id, id, NSURLRequest*, NSURLResponse*, id);

static void traceDidFinishLoading(id self, SEL _cmd, id webView, id resource, id dataSource)
{
    logf_("didFinishLoading %s\n", [[resource description] UTF8String]);
    originalDidFinishLoading(self, _cmd, webView, resource, dataSource);
}

static void traceDidFailLoading(id self, SEL _cmd, id webView, id resource, NSError* error, id dataSource)
{
    logf_("didFailLoading %s: %s\n", [[resource description] UTF8String], error.description.UTF8String);
    originalDidFailLoading(self, _cmd, webView, resource, error, dataSource);
}

static id traceWillSendRequest(id self, SEL _cmd, id webView, id resource, NSURLRequest* request, NSURLResponse* redirect, id dataSource)
{
    id result = originalWillSendRequest(self, _cmd, webView, resource, request, redirect, dataSource);
    logf_("willSendRequest %s -> %s\n", request.URL.absoluteString.UTF8String, [[result URL] absoluteString].UTF8String ?: "(nil)");
    return result;
}

static void traceAuthentication(void)
{
    Class tab = objc_getClass("TabDocumentWK1");
    Method can = class_getInstanceMethod(tab, sel_registerName("webView:resource:canAuthenticateAgainstProtectionSpace:forDataSource:"));
    Method receive = class_getInstanceMethod(tab, sel_registerName("webView:resource:didReceiveAuthenticationChallenge:fromDataSource:"));
    if (can)
        originalCanAuthenticate = (void*)method_setImplementation(can, (IMP)traceCanAuthenticate);
    if (receive)
        originalDidReceiveChallenge = (void*)method_setImplementation(receive, (IMP)traceDidReceiveChallenge);
    Method finish = class_getInstanceMethod(tab, sel_registerName("webThreadWebView:resource:didFinishLoadingFromDataSource:"));
    Method fail = class_getInstanceMethod(tab, sel_registerName("webThreadWebView:resource:didFailLoadingWithError:fromDataSource:"));
    Method send = class_getInstanceMethod(tab, sel_registerName("webThreadWebView:resource:willSendRequest:redirectResponse:fromDataSource:"));
    if (finish)
        originalDidFinishLoading = (void*)method_setImplementation(finish, (IMP)traceDidFinishLoading);
    if (fail)
        originalDidFailLoading = (void*)method_setImplementation(fail, (IMP)traceDidFailLoading);
    if (send)
        originalWillSendRequest = (void*)method_setImplementation(send, (IMP)traceWillSendRequest);
}

// MARK: - Screenshot

static void screenshot(CFNotificationCenterRef center, void* observer, CFStringRef name, const void* object, CFDictionaryRef info)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow* window = [UIApplication sharedApplication].keyWindow;
        UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 0);
        [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        UIImage* image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        BOOL written = [UIImagePNGRepresentation(image) writeToFile:@"/var/mobile/Media/webporn/safari.png" atomically:NO];
        logf_("screenshot %.0fx%.0f: %s\n", image.size.width, image.size.height, written ? "written" : "write failed");
    });
}

// MARK: - Entry

__attribute__((constructor)) static void webPornSafari(void)
{
    @autoreleasepool {
        if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.mobilesafari"])
            return;
        // Only together with the engine swap (Settings > WebPorn > Safari).
        NSDictionary* settings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/net.webporn.swap.plist"];
        if (![[settings objectForKey:@"Enabled-com.apple.mobilesafari"] boolValue])
            return;
        logFile = fopen(LOG_PATH, "w");
        safariHeader = _dyld_get_image_header(0);
        useLegacyWebKit();
        installMissingSelectorFallback();
        traceAuthentication();
        traceDelegateMethods();
        traceEngineCalls();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, screenshot,
            CFSTR("net.webporn.screenshot"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        logf_("WebPornSafari in pid %d: UseLegacyWebKit on, missing-selector fallback installed\n", getpid());
    }
}
