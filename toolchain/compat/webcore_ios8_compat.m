// Foundation / QuartzCore constants WebCore links against that iOS 8.4.1 lacks,
// and methods WebCore sends that iOS 8 classes do not implement (these are not
// link errors, so check-undefs.py cannot see them; they would be
// unrecognized-selector crashes). Linked hidden into WebCore.

#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <CoreGraphics/CGBase.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 110000

// iOS 13. CookieCocoa.mm writes the policy under the "SameSite" property key.
NSString * const NSHTTPCookieSameSitePolicy = @"SameSite";
NSString * const NSHTTPCookieSameSiteLax = @"lax";
NSString * const NSHTTPCookieSameSiteStrict = @"strict";

// Never posted here, so the observers are simply never called.
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 90000
NSString * const NSProcessInfoPowerStateDidChangeNotification = @"NSProcessInfoPowerStateDidChangeNotification";
#endif
NSString * const NSProcessInfoThermalStateDidChangeNotification = @"NSProcessInfoThermalStateDidChangeNotification";

// Unknown compositing filters and contents formats are ignored by older CA.
NSString * const kCAContentsFormatRGBA10XR = @"RGBA10XR";
NSString * const kCAFilterColorBlendMode = @"colorBlendMode";
NSString * const kCAFilterHueBlendMode = @"hueBlendMode";
NSString * const kCAFilterLuminosityBlendMode = @"luminosityBlendMode";
NSString * const kCAFilterSaturationBlendMode = @"saturationBlendMode";

// MARK: - Method shims

static id returnNil(id self, SEL _cmd) { return nil; }
static BOOL returnNO(id self, SEL _cmd) { return NO; }
static BOOL returnYES(id self, SEL _cmd) { return YES; }
static NSInteger returnZero(id self, SEL _cmd) { return 0; }
static void ignoreObject(id self, SEL _cmd, id object) { }
static void ignoreBool(id self, SEL _cmd, BOOL value) { }
static void ignoreObjectObject(id self, SEL _cmd, id a, id b) { }
static BOOL ignoreObjectWithError(id self, SEL _cmd, id object, NSError **error) { return YES; }

// NSHTTPCookie / NSHTTPCookieStorage: the CFNetwork SPI NetworkStorageSessionCocoa
// uses for every cookie read and write, over the public iOS 8 API (no partitions,
// no SameSite enforcement, which CFNetwork 8 does not do either).

static id cookieSameSitePolicy(NSHTTPCookie *self, SEL _cmd)
{
    // NSHTTPCookie keeps unknown attributes; lower-case like the iOS 13 values.
    id policy = self.properties[NSHTTPCookieSameSitePolicy];
    return [policy isKindOfClass:[NSString class]] ? [policy lowercaseString] : nil;
}

static id cookieForSetCookieString(id self, SEL _cmd, NSString *string, NSURL *url, NSString *partition)
{
    if (!string || !url)
        return nil;
    return [NSHTTPCookie cookiesWithResponseHeaderFields:@{ @"Set-Cookie": string } forURL:url].firstObject;
}

static void storageGetCookiesForURL(NSHTTPCookieStorage *self, SEL _cmd, NSURL *url, NSURL *mainDocumentURL, NSString *partition, NSDictionary *policy, void (^completionHandler)(NSArray *))
{
    if (completionHandler)
        completionHandler(url ? [self cookiesForURL:url] : @[]);
}

static void storageSetCookiesForURL(NSHTTPCookieStorage *self, SEL _cmd, NSArray *cookies, NSURL *url, NSURL *mainDocumentURL, NSDictionary *policy)
{
    [self setCookies:cookies forURL:url mainDocumentURL:mainDocumentURL];
}

static NSArray *storageGetCookiesForDomain(NSHTTPCookieStorage *self, SEL _cmd, NSString *domain)
{
    NSMutableArray *result = [NSMutableArray array];
    for (NSHTTPCookie *cookie in self.cookies) {
        NSString *cookieDomain = cookie.domain;
        if ([cookieDomain hasPrefix:@"."])
            cookieDomain = [cookieDomain substringFromIndex:1];
        if ([cookieDomain caseInsensitiveCompare:domain] == NSOrderedSame)
            [result addObject:cookie];
    }
    return result;
}

static void storageSaveCookies(id self, SEL _cmd, void (^completionHandler)(void))
{
    if (completionHandler)
        completionHandler();
}

// Foundation API from iOS 10-12.

static NSData *archivedDataRequiringSecureCoding(id self, SEL _cmd, id object, BOOL requiresSecureCoding, NSError **error)
{
    if (error)
        *error = nil;
    @try {
        return [NSKeyedArchiver archivedDataWithRootObject:object];
    } @catch (NSException *) {
        return nil;
    }
}

static id unarchivedObjectOfClass(id self, SEL _cmd, Class cls, NSData *data, NSError **error)
{
    if (error)
        *error = nil;
    @try {
        id object = data ? [NSKeyedUnarchiver unarchiveObjectWithData:data] : nil;
        return [object isKindOfClass:cls] ? object : nil;
    } @catch (NSException *) {
        return nil;
    }
}

static id urlInitWithDataRepresentation(NSURL *self, SEL _cmd, NSData *data, NSURL *baseURL)
{
    CFURLRef url = CFURLCreateWithBytes(NULL, data.bytes, data.length, kCFStringEncodingUTF8, (__bridge CFURLRef)baseURL);
    if (!url)
        url = CFURLCreateWithBytes(NULL, data.bytes, data.length, kCFStringEncodingISOLatin1, (__bridge CFURLRef)baseURL);
    return url ? [self initWithString:[(__bridge NSURL *)url relativeString] relativeToURL:baseURL] : nil;
}

@interface WPTimerBlockTarget : NSObject
@property (nonatomic, copy) void (^block)(NSTimer *);
@end
@implementation WPTimerBlockTarget
- (void)fire:(NSTimer *)timer { if (_block) _block(timer); }
@end

static NSTimer *scheduledTimerWithBlock(id self, SEL _cmd, NSTimeInterval interval, BOOL repeats, void (^block)(NSTimer *))
{
    WPTimerBlockTarget *target = [WPTimerBlockTarget new];
    target.block = block;
    return [NSTimer scheduledTimerWithTimeInterval:interval target:target selector:@selector(fire:) userInfo:nil repeats:repeats];
}

// -[NSAttributedString _htmlDocumentFragmentString:...] (pasting rich text):
// export through the iOS 7 HTML writer and keep what is inside <body>.
static NSString *htmlDocumentFragmentString(NSAttributedString *self, SEL _cmd, NSRange range, NSDictionary *attributes, NSArray **subresources)
{
    if (subresources)
        *subresources = nil;
    // UIKit's NSDocumentTypeDocumentAttribute / NSHTMLTextDocumentType, by value:
    // WebCore soft-links UIKit, so its constants cannot be linked here.
    NSData *data = ((NSData *(*)(id, SEL, NSRange, NSDictionary *, NSError **))objc_msgSend)(self,
        @selector(dataFromRange:documentAttributes:error:), range, @{ @"DocumentType": @"NSHTML" }, nil);
    NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (!html)
        return [[self.string substringWithRange:range] stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    NSRange bodyStart = [html rangeOfString:@"<body>" options:NSCaseInsensitiveSearch];
    NSRange bodyEnd = [html rangeOfString:@"</body>" options:NSCaseInsensitiveSearch | NSBackwardsSearch];
    if (bodyStart.location == NSNotFound || bodyEnd.location == NSNotFound || bodyEnd.location < NSMaxRange(bodyStart))
        return html;
    // The <head> carries the class-based CSS the body refers to.
    NSRange styleStart = [html rangeOfString:@"<style" options:NSCaseInsensitiveSearch];
    NSRange styleEnd = [html rangeOfString:@"</style>" options:NSCaseInsensitiveSearch];
    NSString *style = (styleStart.location != NSNotFound && styleEnd.location != NSNotFound && styleEnd.location > styleStart.location)
        ? [html substringWithRange:NSMakeRange(styleStart.location, NSMaxRange(styleEnd) - styleStart.location)] : @"";
    return [style stringByAppendingString:[html substringWithRange:NSMakeRange(NSMaxRange(bodyStart), bodyEnd.location - NSMaxRange(bodyStart))]];
}

// UIKit (iOS 9-11). WebCore soft-links UIKit, so no UIKit types here.
typedef struct { CGFloat top, left, bottom, right; } WPEdgeInsets;
static WPEdgeInsets zeroEdgeInsets(id self, SEL _cmd) { return (WPEdgeInsets) { 0, 0, 0, 0 }; }
static void ignoreCall(id self, SEL _cmd) { }
static id viewIfLoaded(id self, SEL _cmd)
{
    return ((BOOL (*)(id, SEL))objc_msgSend)(self, @selector(isViewLoaded)) ? ((id (*)(id, SEL))objc_msgSend)(self, @selector(view)) : nil;
}

// CADisplayLink.preferredFramesPerSecond is iOS 10; before that, frameInterval
// counts 60 Hz frames. (An exception here would unwind through WebCore's
// -fno-exceptions frames with DisplayRefreshMonitor's lock held.)
static void displayLinkSetPreferredFramesPerSecond(id self, SEL _cmd, NSInteger framesPerSecond)
{
    NSInteger interval = framesPerSecond > 0 ? MAX(1, (60 + framesPerSecond / 2) / framesPerSecond) : 1;
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(self, @selector(setFrameInterval:), interval);
}

static NSInteger displayLinkPreferredFramesPerSecond(id self, SEL _cmd)
{
    NSInteger interval = ((NSInteger (*)(id, SEL))objc_msgSend)(self, @selector(frameInterval));
    return interval > 0 ? 60 / interval : 60;
}

// +[UIApplication _classicMode] is an instance method before iOS 9.
static NSInteger applicationClassicMode(id self, SEL _cmd)
{
    id application = ((id (*)(id, SEL))objc_msgSend)(self, @selector(sharedApplication));
    if (!application || !class_respondsToSelector(object_getClass(application), _cmd))
        return 0;
    return ((NSInteger (*)(id, SEL))objc_msgSend)(application, _cmd);
}

// NSLocale (iOS 10-11): language negotiation (text tracks, Intl) and parseLocale().
static id localeComponent(NSLocale *self, NSString *key) { return [self objectForKey:key]; }
static id localeLanguageCode(NSLocale *self, SEL _cmd) { return localeComponent(self, NSLocaleLanguageCode); }
static id localeScriptCode(NSLocale *self, SEL _cmd) { return localeComponent(self, NSLocaleScriptCode); }
static id localeCountryCode(NSLocale *self, SEL _cmd) { return localeComponent(self, NSLocaleCountryCode); }
// The available languages that match the preferred ones, best first: an exact
// identifier, then the same language (the part before '-' or '_').
static NSArray *matchedLanguages(id self, SEL _cmd, NSArray<NSString *> *available, NSArray<NSString *> *preferred)
{
    NSString *(^base)(NSString *) = ^(NSString *language) {
        return [[language componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]].firstObject lowercaseString];
    };
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *wanted in preferred) {
        for (NSString *candidate in available) {
            if ([candidate caseInsensitiveCompare:wanted] == NSOrderedSame && ![matches containsObject:candidate])
                [matches addObject:candidate];
        }
        for (NSString *candidate in available) {
            if ([base(candidate) isEqualToString:base(wanted)] && ![matches containsObject:candidate])
                [matches addObject:candidate];
        }
    }
    return matches;
}

// -[NSCoder decodeValueOfObjCType:at:size:] is iOS 11 (old, non-keyed archives).
static void decodeValueWithSize(NSCoder *self, SEL _cmd, const char *type, void *data, NSUInteger size)
{
    [self decodeValueOfObjCType:type at:data];
}

// UIKit (iOS 11-13).
static void performAsDataOwner(id self, SEL _cmd, NSInteger owner, void (^block)(void))
{
    if (block)
        block();
}
// Semantic label colors (drag images): their light-mode values.
static id labelColor(Class self, CGFloat alpha)
{
    return ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(self, @selector(colorWithRed:green:blue:alpha:), 60 / 255.0, 60 / 255.0, 67 / 255.0, alpha);
}
static id secondaryLabelColor(Class self, SEL _cmd) { return labelColor(self, 0.6); }
static id tertiaryLabelColor(Class self, SEL _cmd) { return labelColor(self, 0.3); }
static id quaternaryLabelColor(Class self, SEL _cmd) { return labelColor(self, 0.18); }

// AVFoundation (iOS 9-11).
static id voiceLanguage(id self, SEL _cmd) { return ((id (*)(id, SEL))objc_msgSend)(self, @selector(language)); }
static id voiceWithIdentifier(id self, SEL _cmd, NSString *identifier)
{
    return ((id (*)(id, SEL, id))objc_msgSend)(self, @selector(voiceWithLanguage:), identifier);
}
static BOOL audioSessionSetCategoryModePolicy(id self, SEL _cmd, NSString *category, NSString *mode, NSUInteger policy, NSUInteger options, NSError **error)
{
    BOOL ok = ((BOOL (*)(id, SEL, id, NSUInteger, NSError **))objc_msgSend)(self, @selector(setCategory:withOptions:error:), category, options, error);
    if (ok && mode)
        ok = ((BOOL (*)(id, SEL, id, NSError **))objc_msgSend)(self, @selector(setMode:error:), mode, error);
    return ok;
}
static id speechVoicesIncludingSuperCompact(id self, SEL _cmd)
{
    return ((id (*)(id, SEL))objc_msgSend)(self, @selector(speechVoices));
}
static NSInteger playerTimeControlStatus(id self, SEL _cmd)
{
    // AVPlayerTimeControlStatusPaused = 0, ...Playing = 2
    return ((float (*)(id, SEL))objc_msgSend)(self, @selector(rate)) > 0 ? 2 : 0;
}

#define INTEGER_TYPE (sizeof(NSInteger) == 8 ? "q@:" : "i@:")

static const struct {
    const char* className;
    bool classMethod;
    const char* selector;
    IMP imp;
    const char* types;
} shims[] = {
    { "NSHTTPCookie", false, "sameSitePolicy", (IMP)cookieSameSitePolicy, "@@:" },
    { "NSHTTPCookie", false, "_storagePartition", (IMP)returnNil, "@@:" },
    { "NSHTTPCookie", true, "_cookieForSetCookieString:forURL:partition:", (IMP)cookieForSetCookieString, "@@:@@@" },
    { "NSHTTPCookieStorage", false, "_getCookiesForURL:mainDocumentURL:partition:policyProperties:completionHandler:", (IMP)storageGetCookiesForURL, "v@:@@@@@?" },
    { "NSHTTPCookieStorage", false, "_setCookies:forURL:mainDocumentURL:policyProperties:", (IMP)storageSetCookiesForURL, "v@:@@@@" },
    { "NSHTTPCookieStorage", false, "_getCookiesForDomain:", (IMP)storageGetCookiesForDomain, "@@:@" },
    { "NSHTTPCookieStorage", false, "_saveCookies:", (IMP)storageSaveCookies, "v@:@?" },
    { "NSHTTPCookieStorage", false, "_setCookiesChangedHandler:onQueue:", (IMP)ignoreObjectObject, "v@:@?@" },
    { "NSHTTPCookieStorage", false, "_setCookiesRemovedHandler:onQueue:", (IMP)ignoreObjectObject, "v@:@?@" },
    { "NSHTTPCookieStorage", false, "_setSubscribedDomainsForCookieChanges:", (IMP)ignoreObject, "v@:@" },
    { "NSURLRequest", false, "_privacyProxyFailClosedForUnreachableNonMainHosts", (IMP)returnNO, "c@:" },
    { "NSURLRequest", false, "_useEnhancedPrivacyMode", (IMP)returnNO, "c@:" },
    { "NSMutableURLRequest", false, "_setPrivacyProxyFailClosedForUnreachableNonMainHosts:", (IMP)ignoreBool, "v@:c" },
    { "NSMutableURLRequest", false, "_setUseEnhancedPrivacyMode:", (IMP)ignoreBool, "v@:c" },
    { "NSProcessInfo", false, "isLowPowerModeEnabled", (IMP)returnNO, "c@:" },
    { "NSProcessInfo", false, "lowPowerModeEnabled", (IMP)returnNO, "c@:" },
    { "NSProcessInfo", false, "thermalState", (IMP)returnZero, NULL }, // NSProcessInfoThermalStateNominal
    { "NSKeyedArchiver", true, "archivedDataWithRootObject:requiringSecureCoding:error:", (IMP)archivedDataRequiringSecureCoding, "@@:@c^@" },
    { "NSKeyedUnarchiver", true, "unarchivedObjectOfClass:fromData:error:", (IMP)unarchivedObjectOfClass, "@@:#@^@" },
    { "NSURL", false, "initWithDataRepresentation:relativeToURL:", (IMP)urlInitWithDataRepresentation, "@@:@@" },
    { "NSTimer", true, "scheduledTimerWithTimeInterval:repeats:block:", (IMP)scheduledTimerWithBlock, "@@:dc@?" },
    { "NSAttributedString", false, "_htmlDocumentFragmentString:documentAttributes:subresources:", (IMP)htmlDocumentFragmentString, "@@:{_NSRange=II}@^@" },
    // UITraitCollection exists from iOS 8, the "current" collection only from iOS 13;
    // LocalCurrentTraitCollection saves and restores it around system-color lookups.
    { "UITraitCollection", true, "currentTraitCollection", (IMP)returnNil, "@@:" },
    { "UITraitCollection", true, "setCurrentTraitCollection:", (IMP)ignoreObject, "v@:@" },
    { "CADisplayLink", false, "setPreferredFramesPerSecond:", (IMP)displayLinkSetPreferredFramesPerSecond, sizeof(NSInteger) == 8 ? "v@:q" : "v@:i" },
    { "CADisplayLink", false, "preferredFramesPerSecond", (IMP)displayLinkPreferredFramesPerSecond, NULL },
    { "UIApplication", true, "_classicMode", (IMP)applicationClassicMode, NULL },
    { "UIView", false, "safeAreaInsets", (IMP)zeroEdgeInsets, "{UIEdgeInsets=ffff}@:" },
    { "UIViewController", false, "viewSafeAreaInsetsDidChange", (IMP)ignoreCall, "v@:" },
    { "UIViewController", false, "viewIfLoaded", (IMP)viewIfLoaded, "@@:" },
    { "AVSpeechSynthesisVoice", false, "isSystemVoice", (IMP)returnYES, "c@:" },
    { "AVSpeechSynthesisVoice", false, "identifier", (IMP)voiceLanguage, "@@:" },
    { "AVSpeechSynthesisVoice", false, "name", (IMP)voiceLanguage, "@@:" },
    { "AVSpeechSynthesisVoice", true, "voiceWithIdentifier:", (IMP)voiceWithIdentifier, "@@:@" },
    { "AVAudioSession", false, "routeSharingPolicy", (IMP)returnZero, NULL },
    { "AVAudioSession", false, "setCategory:mode:routeSharingPolicy:options:error:", (IMP)audioSessionSetCategoryModePolicy, "c@:@@II^@" },
    { "AVAudioSession", false, "setAuditTokensForProcessAssertion:error:", (IMP)ignoreObjectWithError, "c@:@^@" },
    { "AVPlayer", false, "automaticallyWaitsToMinimizeStalling", (IMP)returnNO, "c@:" },
    { "AVPlayer", false, "setAutomaticallyWaitsToMinimizeStalling:", (IMP)ignoreBool, "v@:c" },
    { "AVPlayer", false, "timeControlStatus", (IMP)playerTimeControlStatus, NULL },
    { "AVPlayer", false, "_setPreventsSleepDuringVideoPlayback:", (IMP)ignoreBool, "v@:c" },
    { "AVPlayerItem", false, "addMediaDataCollector:", (IMP)ignoreObject, "v@:@" },
    { "WebFilterEvaluator", true, "isManagedSession", (IMP)returnNO, "c@:" },
    { "NSLocale", false, "languageCode", (IMP)localeLanguageCode, "@@:" },
    { "NSLocale", false, "scriptCode", (IMP)localeScriptCode, "@@:" },
    { "NSLocale", false, "countryCode", (IMP)localeCountryCode, "@@:" },
    { "NSLocale", true, "matchedLanguagesFromAvailableLanguages:forPreferredLanguages:", (IMP)matchedLanguages, "@@:@@" },
    { "NSCoder", false, "decodeValueOfObjCType:at:size:", (IMP)decodeValueWithSize, sizeof(NSUInteger) == 8 ? "v@:*^vQ" : "v@:*^vI" },
    { "UIPasteboard", true, "_performAsDataOwner:block:", (IMP)performAsDataOwner, sizeof(NSInteger) == 8 ? "v@:q@?" : "v@:i@?" },
    { "UIColor", true, "secondaryLabelColor", (IMP)secondaryLabelColor, "@@:" },
    { "UIColor", true, "tertiaryLabelColor", (IMP)tertiaryLabelColor, "@@:" },
    { "UIColor", true, "quaternaryLabelColor", (IMP)quaternaryLabelColor, "@@:" },
    { "AVSpeechSynthesisVoice", true, "speechVoicesIncludingSuperCompact", (IMP)speechVoicesIncludingSuperCompact, "@@:" },
    { "AVAudioSession", false, "routingContextUID", (IMP)returnNil, "@@:" },
};

// Classes from frameworks loaded after WebCore (AVFoundation, UIKit,
// WebContentAnalysis) get their methods when their image is added.
static void installShims(const struct mach_header* header, intptr_t slide)
{
    static bool done[sizeof(shims) / sizeof(shims[0])];
    for (size_t i = 0; i < sizeof(shims) / sizeof(shims[0]); i++) {
        if (done[i])
            continue;
        Class cls = objc_getClass(shims[i].className);
        if (!cls)
            continue;
        done[i] = true;
        if (shims[i].classMethod)
            cls = object_getClass(cls);
        SEL selector = sel_registerName(shims[i].selector);
        if (!class_respondsToSelector(cls, selector))
            class_addMethod(cls, selector, shims[i].imp, shims[i].types ? shims[i].types : INTEGER_TYPE);
    }
}

__attribute__((constructor)) static void installWebCoreSelectorShims(void)
{
    _dyld_register_func_for_add_image(installShims);
}

#endif
