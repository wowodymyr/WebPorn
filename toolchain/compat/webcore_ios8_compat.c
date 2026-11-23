// CoreText / CoreGraphics / CommonCrypto / libSystem entry points WebCore links
// against that iOS 8.4.1 does not export (device/iphone5-8.4.1/missing-WebCore.txt).
// This is the job of Web Port's runtime stubs lib: where an older API can do the
// work it is used, otherwise the stub fails in the way the WK26 call sites expect
// (NULL color spaces, failing corecrypto, ...). Linked hidden into WebCore, and
// -load_hidden puts it ahead of the SDK .tbds, so these win over the SDK imports.

#include <CommonCrypto/CommonCryptor.h>
#include <CommonCrypto/CommonHMAC.h>
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <CoreText/CoreText.h>
#include <ImageIO/ImageIO.h>
#include <dlfcn.h>
#include <Security/Security.h>
#include <limits.h>
#include <math.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 110000

// Older CoreText SPI that iOS 8 does export.
typedef CF_OPTIONS(uint32_t, WPCTFontTransformOptions) {
    WPCTFontTransformApplyShaping = 1 << 0,
    WPCTFontTransformApplyPositioning = 1 << 1,
};
extern CFIndex CTFontTransformGlyphs(CTFontRef, CGGlyph[], CGSize[], CFIndex, WPCTFontTransformOptions);
extern CTFontRef CTFontCreateForStringWithLanguage(CTFontRef, CFStringRef, CFRange, CFStringRef);
extern CTFontDescriptorRef CTFontDescriptorCreateForUIType(CTFontUIFontType, CGFloat, CFStringRef);
extern bool CTFontIsAppleColorEmoji(CTFontRef);
extern CGImageRef CGIOSurfaceContextCreateImage(CGContextRef);
typedef int32_t WPCCStatus;
extern int timingsafe_bcmp(const void*, const void*, size_t);
extern WPCCStatus CCCryptorGCM(CCOperation, CCAlgorithm, const void*, size_t, const void*, size_t,
    const void*, size_t, const void*, size_t, void*, void*, size_t*);

// MARK: - SQLite

int sqlite3_bind_blob64(sqlite3_stmt* statement, int index, const void* data, sqlite3_uint64 size, void (*destructor)(void*))
{
    if (size > INT_MAX) {
        if (destructor && destructor != SQLITE_STATIC && destructor != SQLITE_TRANSIENT)
            destructor((void*)data);
        return SQLITE_TOOBIG;
    }
    return sqlite3_bind_blob(statement, index, data, (int)size, destructor);
}

// MARK: - CommonCrypto / corecrypto

enum { WPCCSuccess = 0, WPCCParamError = -4300, WPCCDecodeError = -4304, WPCCUnimplemented = -4305 };

struct CCKDFParameters {
    void* salt;
    size_t saltLength;
    void* info;
    size_t infoLength;
};

static void* copyBytes(const void* bytes, size_t length)
{
    void* copy = malloc(length ? length : 1);
    if (copy && length)
        memcpy(copy, bytes, length);
    return copy;
}

WPCCStatus CCKDFParametersCreateHkdf(struct CCKDFParameters** params, const void* salt, size_t saltLength, const void* context, size_t contextLength)
{
    struct CCKDFParameters* result = calloc(1, sizeof(*result));
    if (!result)
        return WPCCParamError;
    result->salt = copyBytes(salt, saltLength);
    result->saltLength = saltLength;
    result->info = copyBytes(context, contextLength);
    result->infoLength = contextLength;
    *params = result;
    return WPCCSuccess;
}

void CCKDFParametersDestroy(struct CCKDFParameters* params)
{
    if (!params)
        return;
    free(params->salt);
    free(params->info);
    free(params);
}

// RFC 5869 over CCHmac. Digest values are CommonDigestSPI's kCCDigestSHA*.
WPCCStatus CCDeriveKey(const struct CCKDFParameters* params, int digest, const void* keyDerivationKey, size_t keyDerivationKeyLength, void* derivedKey, size_t derivedKeyLength)
{
    CCHmacAlgorithm algorithm;
    size_t hashLength;
    switch (digest) {
    case 8: algorithm = kCCHmacAlgSHA1; hashLength = 20; break;
    case 9: algorithm = kCCHmacAlgSHA224; hashLength = 28; break;
    case 10: algorithm = kCCHmacAlgSHA256; hashLength = 32; break;
    case 11: algorithm = kCCHmacAlgSHA384; hashLength = 48; break;
    case 12: algorithm = kCCHmacAlgSHA512; hashLength = 64; break;
    default: return WPCCParamError;
    }
    if (!params || derivedKeyLength > 255 * hashLength)
        return WPCCParamError;

    unsigned char zeroSalt[64] = { 0 };
    unsigned char prk[64];
    CCHmac(algorithm, params->saltLength ? params->salt : zeroSalt, params->saltLength ? params->saltLength : hashLength,
        keyDerivationKey, keyDerivationKeyLength, prk);

    unsigned char block[64];
    unsigned char* out = derivedKey;
    for (unsigned counter = 1, done = 0; done < derivedKeyLength; counter++) {
        CCHmacContext context;
        CCHmacInit(&context, algorithm, prk, hashLength);
        if (counter > 1)
            CCHmacUpdate(&context, block, hashLength);
        CCHmacUpdate(&context, params->info, params->infoLength);
        unsigned char counterByte = counter;
        CCHmacUpdate(&context, &counterByte, 1);
        CCHmacFinal(&context, block);
        size_t chunk = derivedKeyLength - done < hashLength ? derivedKeyLength - done : hashLength;
        memcpy(out + done, block, chunk);
        done += chunk;
    }
    memset(prk, 0, sizeof(prk));
    memset(block, 0, sizeof(block));
    return WPCCSuccess;
}

// The iOS 6+ GCM one-shot computes the tag instead of checking it.
WPCCStatus CCCryptorGCMOneshotDecrypt(CCAlgorithm algorithm, const void* key, size_t keyLength, const void* iv, size_t ivLength,
    const void* aData, size_t aDataLength, const void* dataIn, size_t dataInLength, void* dataOut, const void* tagIn, size_t tagLength)
{
    unsigned char tag[16];
    size_t computedTagLength = tagLength;
    if (tagLength > sizeof(tag))
        return WPCCParamError;
    WPCCStatus status = CCCryptorGCM(kCCDecrypt, algorithm, key, keyLength, iv, ivLength, aData, aDataLength,
        dataIn, dataInLength, dataOut, tag, &computedTagLength);
    if (status)
        return status;
    if (computedTagLength != tagLength || timingsafe_bcmp(tag, tagIn, tagLength)) {
        memset(dataOut, 0, dataInLength);
        return WPCCDecodeError;
    }
    return WPCCSuccess;
}

// No bignum API to derive dp/dq/qinv from; exporting an RSA private key as JWK fails.
WPCCStatus CCRSAGetCRTComponentsSizes(void* rsaKey, size_t* dpSize, size_t* dqSize, size_t* qinvSize) { return WPCCUnimplemented; }
WPCCStatus CCRSAGetCRTComponents(void* rsaKey, void* dp, size_t dpSize, void* dq, size_t dqSize, void* qinv, size_t qinvSize) { return WPCCUnimplemented; }

// No Curve25519 in iOS 8 corecrypto; the WK26 call sites expect these to fail.
int cccurve25519_make_pub(void* publicKey, const void* secretKey) { return -1; }
int cced25519_make_pub(const void* digestInfo, void* publicKey, const void* secretKey) { return -1; }

// MARK: - Security / CFNetwork / CoreFoundation

int SecCertificateGetSignatureHashAlgorithm(SecCertificateRef certificate) { return 0; } // kSecSignatureHashAlgorithmUnknown
CFDataRef SecTrustSerialize(SecTrustRef trust, CFErrorRef* error) { if (error) *error = NULL; return NULL; }
SecTrustRef SecTrustDeserialize(CFDataRef data, CFErrorRef* error) { if (error) *error = NULL; return NULL; }
OSStatus SecTrustSetClientAuditToken(SecTrustRef trust, CFDataRef token) { return errSecSuccess; }
void _CFURLStorageSessionDisableCache(const void* session) { }
Boolean _CFRunLoopSetPerCalloutAutoreleasepoolEnabled(Boolean enabled) { return false; }

// MARK: - CoreGraphics / ImageIO

// Names match the real constants, so CG on newer systems and CFEqual-based
// lookups see the same strings; iOS 8 CGColorSpaceCreateWithName returns NULL
// for them and ColorSpaceCG.cpp falls back to device RGB.
const CFStringRef kCGColorSpaceDisplayP3 = CFSTR("kCGColorSpaceDisplayP3");
const CFStringRef kCGColorSpaceExtendedDisplayP3 = CFSTR("kCGColorSpaceExtendedDisplayP3");
const CFStringRef kCGColorSpaceExtendedITUR_2020 = CFSTR("kCGColorSpaceExtendedITUR_2020");
const CFStringRef kCGColorSpaceExtendedLinearDisplayP3 = CFSTR("kCGColorSpaceExtendedLinearDisplayP3");
const CFStringRef kCGColorSpaceExtendedLinearSRGB = CFSTR("kCGColorSpaceExtendedLinearSRGB");
const CFStringRef kCGColorSpaceExtendedSRGB = CFSTR("kCGColorSpaceExtendedSRGB");
const CFStringRef kCGColorSpaceGenericXYZ = CFSTR("kCGColorSpaceGenericXYZ");
const CFStringRef kCGColorSpaceITUR_2020 = CFSTR("kCGColorSpaceITUR_2020");
const CFStringRef kCGColorSpaceLinearDisplayP3 = CFSTR("kCGColorSpaceLinearDisplayP3");
const CFStringRef kCGColorSpaceLinearSRGB = CFSTR("kCGColorSpaceLinearSRGB");
const CFStringRef kCGColorSpaceROMMRGB = CFSTR("kCGColorSpaceROMMRGB");
const CFStringRef kCGGradientInterpolatesPremultiplied = CFSTR("kCGGradientInterpolatesPremultiplied");
const CFStringRef kCGImagePropertyImageCount = CFSTR("ImageCount");

CGColorSpaceRef CGColorSpaceCreateExtended(CGColorSpaceRef space) { return NULL; }
bool CGColorSpaceUsesExtendedRange(CGColorSpaceRef space) { return false; }
CGColorSpaceRef CGColorSpaceCreateCopyWithStandardRange(CGColorSpaceRef space) { return CGColorSpaceRetain(space); }

// Every color space WebCore can get here is RGB-model (named spaces collapse to
// device RGB), so reinterpreting the components is the identity conversion.
CGColorRef CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceRef space, CGColorRenderingIntent intent, CGColorRef color, CFDictionaryRef options)
{
    if (!color)
        return NULL;
    CGColorSpaceRef source = CGColorGetColorSpace(color);
    if (!space || source == space || CFEqual(source, space))
        return CGColorRetain(color);
    if (CGColorSpaceGetModel(source) != CGColorSpaceGetModel(space) || CGColorGetNumberOfComponents(color) != CGColorSpaceGetNumberOfComponents(space) + 1)
        return CGColorRetain(color);
    return CGColorCreate(space, CGColorGetComponents(color));
}

CGGradientRef CGGradientCreateWithColorComponentsAndOptions(CGColorSpaceRef space, const CGFloat* components, const CGFloat* locations, size_t count, CFDictionaryRef options)
{
    return CGGradientCreateWithColorComponents(space, components, locations, count);
}

// Conic gradients: sample the ramp into a strip, then fill wedges around the
// center. Parameter t runs from `angle` (radians from +x) in the direction of +y,
// which is clockwise on screen in WebCore's flipped, pre-rotated space.
enum { ConicSteps = 256 };

static void drawConicStrip(CGContextRef context, CGPoint center, CGFloat angle, const uint8_t* rgba)
{
    CGRect clip = CGContextGetClipBoundingBox(context);
    CGFloat radius = 0;
    CGPoint corners[4] = {
        { CGRectGetMinX(clip), CGRectGetMinY(clip) }, { CGRectGetMaxX(clip), CGRectGetMinY(clip) },
        { CGRectGetMinX(clip), CGRectGetMaxY(clip) }, { CGRectGetMaxX(clip), CGRectGetMaxY(clip) },
    };
    for (int i = 0; i < 4; i++)
        radius = fmax(radius, hypot(corners[i].x - center.x, corners[i].y - center.y));
    if (!(radius > 0) || !isfinite(radius))
        return;
    radius += 1;

    CGContextSaveGState(context);
    CGContextSetShouldAntialias(context, false); // seams between wedges otherwise
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextSetFillColorSpace(context, rgb);
    CGColorSpaceRelease(rgb);
    for (int i = 0; i < ConicSteps; i++) {
        const uint8_t* p = rgba + 4 * i;
        CGFloat alpha = p[3] / 255.0;
        CGFloat color[4] = { 0, 0, 0, alpha };
        if (p[3]) { // un-premultiply
            color[0] = fmin(1, p[0] / 255.0 / alpha);
            color[1] = fmin(1, p[1] / 255.0 / alpha);
            color[2] = fmin(1, p[2] / 255.0 / alpha);
        }
        CGContextSetFillColor(context, color);
        CGFloat a0 = angle + 2 * M_PI * i / ConicSteps;
        CGFloat a1 = angle + 2 * M_PI * (i + 1.02) / ConicSteps; // slight overlap
        CGContextBeginPath(context);
        CGContextMoveToPoint(context, center.x, center.y);
        CGContextAddLineToPoint(context, center.x + radius * cos(a0), center.y + radius * sin(a0));
        CGContextAddLineToPoint(context, center.x + radius * cos(a1), center.y + radius * sin(a1));
        CGContextClosePath(context);
        CGContextFillPath(context);
    }
    CGContextRestoreGState(context);
}

static CGContextRef createStripContext(uint8_t* rgba)
{
    CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
    CGContextRef strip = CGBitmapContextCreate(rgba, ConicSteps, 1, 8, 4 * ConicSteps, rgb, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(rgb);
    return strip;
}

void CGContextDrawConicGradient(CGContextRef context, CGGradientRef gradient, CGPoint center, CGFloat angle)
{
    uint8_t rgba[4 * ConicSteps] = { 0 };
    CGContextRef strip = createStripContext(rgba);
    if (!strip)
        return;
    // Sample at pixel centers so t=0 and t=1 land on the first and last stops.
    CGContextDrawLinearGradient(strip, gradient, CGPointMake(0.5, 0), CGPointMake(ConicSteps - 0.5, 0),
        kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
    CGContextRelease(strip);
    drawConicStrip(context, center, angle, rgba);
}

// No way to make a custom CGShading; approximate with an axial shading along the
// start direction. Only the Shading strategy (non-sRGB interpolation) gets here.
CGShadingRef CGShadingCreateConic(CGColorSpaceRef space, CGPoint center, CGFloat angle, CGFunctionRef function)
{
    CGPoint end = CGPointMake(center.x + 100 * cos(angle), center.y + 100 * sin(angle));
    return CGShadingCreateAxial(space, center, end, function, true, true);
}

void CGContextDrawPathDirect(CGContextRef context, CGPathDrawingMode mode, CGPathRef path, const CGRect* boundingBox)
{
    CGContextBeginPath(context);
    CGContextAddPath(context, path);
    CGContextDrawPath(context, mode);
}

void CGContextDrawPDFPageWithAnnotations(CGContextRef context, CGPDFPageRef page, void* annotationCallback)
{
    CGContextDrawPDFPage(context, page);
}

CGImageRef CGIOSurfaceContextCreateImageReference(CGContextRef context)
{
    return CGIOSurfaceContextCreateImage(context);
}

OSStatus CGImageSourceSetAllowableTypes(CFArrayRef allowableTypes) { return 0; }

// corners[] is BottomLeft, BottomRight, TopRight, TopLeft (PathCG.cpp), where
// "top" is minY in WebCore's flipped coordinates.
void CGPathAddUnevenCornersRoundedRect(CGMutablePathRef path, const CGAffineTransform* transform, CGRect rect, const CGSize corners[4])
{
    const CGFloat k = 0.44771525; // 1 - 4/3 * (sqrt(2) - 1): cubic quarter-ellipse control offset
    CGFloat minX = CGRectGetMinX(rect), maxX = CGRectGetMaxX(rect);
    CGFloat minY = CGRectGetMinY(rect), maxY = CGRectGetMaxY(rect);
    CGSize bl = corners[0], br = corners[1], tr = corners[2], tl = corners[3];

    CGPathMoveToPoint(path, transform, minX + tl.width, minY);
    CGPathAddLineToPoint(path, transform, maxX - tr.width, minY);
    CGPathAddCurveToPoint(path, transform, maxX - tr.width * k, minY, maxX, minY + tr.height * k, maxX, minY + tr.height);
    CGPathAddLineToPoint(path, transform, maxX, maxY - br.height);
    CGPathAddCurveToPoint(path, transform, maxX, maxY - br.height * k, maxX - br.width * k, maxY, maxX - br.width, maxY);
    CGPathAddLineToPoint(path, transform, minX + bl.width, maxY);
    CGPathAddCurveToPoint(path, transform, minX + bl.width * k, maxY, minX, maxY - bl.height * k, minX, maxY - bl.height);
    CGPathAddLineToPoint(path, transform, minX, minY + tl.height);
    CGPathAddCurveToPoint(path, transform, minX, minY + tl.height * k, minX + tl.width * k, minY, minX + tl.width, minY);
    CGPathCloseSubpath(path);
}

// iOS 8 CGStyle has shadows and focus rings only; a NULL style clears the
// context's style, so blur / color-matrix filters draw unfiltered.
const void* CGStyleCreateGaussianBlur(const void* style) { return NULL; }
const void* CGStyleCreateColorMatrix(const void* style) { return NULL; }

// MARK: - CoreText

const CFStringRef kCTFontCSSFamilyCursive = CFSTR("cursive");
const CFStringRef kCTFontCSSFamilyFantasy = CFSTR("fantasy");
const CFStringRef kCTFontCSSFamilyMonospace = CFSTR("monospace");
const CFStringRef kCTFontCSSFamilySansSerif = CFSTR("sans-serif");
const CFStringRef kCTFontCSSFamilySerif = CFSTR("serif");
// Attribute and trait keys iOS 8 CoreText ignores.
const CFStringRef kCTFontCSSWeightAttribute = CFSTR("NSCTFontCSSWeightAttribute");
const CFStringRef kCTFontCSSWidthAttribute = CFSTR("NSCTFontCSSWidthAttribute");
const CFStringRef kCTFontDescriptorLanguageAttribute = CFSTR("NSCTFontDescriptorLanguageAttribute");
const CFStringRef kCTFontFallbackOptionAttribute = CFSTR("NSCTFontFallbackOptionAttribute");
const CFStringRef kCTFontGradeTrait = CFSTR("NSCTFontGradeTrait");
const CFStringRef kCTFontIgnoreLegibilityWeightAttribute = CFSTR("NSCTFontIgnoreLegibilityWeightAttribute");
const CFStringRef kCTFontPaletteAttribute = CFSTR("NSCTFontPaletteAttribute");
const CFStringRef kCTFontPaletteColorsAttribute = CFSTR("NSCTFontPaletteColorsAttribute");
const CFStringRef kCTFontSizeCategoryAttribute = CFSTR("NSCTFontSizeCategoryAttribute");
const CFStringRef kCTFontUIFontDesignMonospaced = CFSTR("NSCTFontUIFontDesignMonospaced");
const CFStringRef kCTFontUIFontDesignSerif = CFSTR("NSCTFontUIFontDesignSerif");
const CFStringRef kCTFontUnscaledTrackingAttribute = CFSTR("NSCTFontUnscaledTrackingAttribute");
const CFStringRef kCTFontUserInstalledAttribute = CFSTR("NSCTFontUserInstalledAttribute");
const CFStringRef kCTUIFontTextStyleTitle0 = CFSTR("UICTFontTextStyleTitle0");
const CFStringRef kCTUIFontTextStyleTitle1 = CFSTR("UICTFontTextStyleTitle1");
const CFStringRef kCTUIFontTextStyleTitle2 = CFSTR("UICTFontTextStyleTitle2");
const CFStringRef kCTUIFontTextStyleTitle3 = CFSTR("UICTFontTextStyleTitle3");
const CFStringRef kCTUIFontTextStyleTitle4 = CFSTR("UICTFontTextStyleTitle4");
// Width scale around kCTFontWidthCondensed (-0.2) / Standard (0) / Expanded (0.2).
const CGFloat kCTFontWidthUltraCompressed = -0.5;
const CGFloat kCTFontWidthExtraCompressed = -0.4;
const CGFloat kCTFontWidthExtraCondensed = -0.3;
const CGFloat kCTFontWidthSemiCondensed = -0.1;
const CGFloat kCTFontWidthSemiExpanded = 0.1;
const CGFloat kCTFontWidthExtraExpanded = 0.3;

static void reverseRange(void* base, size_t elementSize, CFIndex count)
{
    unsigned char tmp[16];
    unsigned char* p = base;
    for (CFIndex i = 0, j = count - 1; i < j; i++, j--) {
        memcpy(tmp, p + i * elementSize, elementSize);
        memcpy(p + i * elementSize, p + j * elementSize, elementSize);
        memcpy(p + j * elementSize, tmp, elementSize);
    }
}

// The pre-iOS 10 transform shapes/kerns in place without changing the glyph
// count: glyphs swallowed by a ligature come back as 0xFFFF and are removed
// through the handler. Output is in visual order for RTL, which applyTransforms
// reverses back afterwards.
CGSize CTFontShapeGlyphs(CTFontRef font, CGGlyph glyphs[], CGSize advances[], CGPoint origins[], CFIndex indexes[],
    const UniChar chars[], CFIndex count, uint32_t options, CFStringRef language,
    void (^handler)(CFRange, CGGlyph**, CGSize**, CGPoint**, CFIndex**))
{
    if (count <= 0)
        return CGSizeZero;
    WPCTFontTransformOptions transform = WPCTFontTransformApplyShaping | ((options & 1) ? WPCTFontTransformApplyPositioning : 0);
    CTFontTransformGlyphs(font, glyphs, advances, count, transform);
    for (CFIndex i = 0; i < count; i++)
        origins[i] = CGPointZero;

    for (CFIndex i = count - 1; i >= 0; i--) {
        if (glyphs[i] != 0xFFFF)
            continue;
        if (i > 0) {
            advances[i - 1].width += advances[i].width;
            advances[i - 1].height += advances[i].height;
        }
        handler(CFRangeMake(i + 1, -1), &glyphs, &advances, &origins, &indexes);
        count--;
    }

    if (options & 4) {
        reverseRange(glyphs, sizeof(*glyphs), count);
        reverseRange(advances, sizeof(*advances), count);
        reverseRange(origins, sizeof(*origins), count);
        reverseRange(indexes, sizeof(*indexes), count);
    }
    return CGSizeZero;
}

void CTRunGetBaseAdvancesAndOrigins(CTRunRef run, CFRange range, CGSize baseAdvances[], CGPoint origins[])
{
    CFIndex count = range.length ? range.length : CTRunGetGlyphCount(run) - range.location;
    if (baseAdvances)
        CTRunGetAdvances(run, range, baseAdvances);
    for (CFIndex i = 0; origins && i < count; i++)
        origins[i] = CGPointZero;
}

static CFIndex coveredPrefixLength(CTFontRef font, const UniChar* characters, CFIndex length)
{
    CFIndex covered = 0;
    while (covered < length) {
        CFIndex unit = (CFStringIsSurrogateHighCharacter(characters[covered]) && covered + 1 < length) ? 2 : 1;
        CGGlyph glyph[2] = { 0, 0 };
        if (!CTFontGetGlyphsForCharacters(font, characters + covered, glyph, unit) || !glyph[0])
            break;
        covered += unit;
    }
    return covered;
}

CTFontRef CTFontCreateForCharactersWithLanguageAndOption(CTFontRef currentFont, const UniChar* characters, CFIndex length,
    CFStringRef language, uint32_t fallbackOption, CFIndex* coveredLength)
{
    CFStringRef string = CFStringCreateWithCharactersNoCopy(NULL, characters, length, kCFAllocatorNull);
    CTFontRef result = CTFontCreateForStringWithLanguage(currentFont, string, CFRangeMake(0, length), language);
    CFRelease(string);
    if (!result)
        result = CFRetain(currentFont);
    if (coveredLength) {
        *coveredLength = coveredPrefixLength(result, characters, length);
        if (!*coveredLength) // CoreText's answer for unsupported clusters: the font it picked, for one unit
            *coveredLength = length ? 1 : 0;
    }
    return result;
}

CTFontDescriptorRef CTFontDescriptorCreateForCSSFamily(CFStringRef cssFamily, CFStringRef language)
{
    CFStringRef family = CFSTR("Helvetica");
    if (CFEqual(cssFamily, kCTFontCSSFamilySerif))
        family = CFSTR("Times New Roman");
    else if (CFEqual(cssFamily, kCTFontCSSFamilyMonospace))
        family = CFSTR("Courier");
    else if (CFEqual(cssFamily, kCTFontCSSFamilyCursive))
        family = CFSTR("Snell Roundhand");
    else if (CFEqual(cssFamily, kCTFontCSSFamilyFantasy))
        family = CFSTR("Papyrus");
    const void* keys[] = { kCTFontFamilyNameAttribute };
    const void* values[] = { family };
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CTFontDescriptorRef descriptor = CTFontDescriptorCreateWithAttributes(attributes);
    CFRelease(attributes);
    return descriptor;
}

CTFontDescriptorRef CTFontDescriptorCreateLastResort(void)
{
    return CTFontDescriptorCreateWithNameAndSize(CFSTR("LastResort"), 0);
}

CTFontDescriptorRef CTFontDescriptorCreateWithTextStyleAndAttributes(CFStringRef style, CFStringRef size, CFDictionaryRef attributes)
{
    CTFontDescriptorRef base = CTFontDescriptorCreateForUIType(kCTFontUIFontSystem, 0, NULL);
    if (!base || !attributes)
        return base;
    CTFontDescriptorRef result = CTFontDescriptorCreateCopyWithAttributes(base, attributes);
    CFRelease(base);
    return result;
}

uint32_t CTFontDescriptorGetOptions(CTFontDescriptorRef descriptor) { return 0; }

// Dynamic Type sizes at the default "Large" category.
CGFloat CTFontDescriptorGetTextStyleSize(CFStringRef style, CFTypeRef sizeCategory, uint32_t platform, CGFloat* weight, CGFloat* lineSpacing)
{
    static const struct { const char* suffix; CGFloat size; CGFloat weight; } table[] = {
        { "Title0", 34, 0 }, { "Title1", 28, 0 }, { "Title2", 22, 0 }, { "Title3", 20, 0 }, { "Title4", 17, 0.4 },
        { "Headline", 17, 0.4 }, { "Subhead", 15, 0 }, { "Callout", 16, 0 }, { "Footnote", 13, 0 },
        { "Caption1", 12, 0 }, { "Caption2", 11, 0 }, { "Body", 17, 0 },
    };
    char name[64] = "";
    if (style)
        CFStringGetCString(style, name, sizeof(name), kCFStringEncodingUTF8);
    CGFloat size = 17, styleWeight = 0;
    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        if (strstr(name, table[i].suffix)) {
            size = table[i].size;
            styleWeight = table[i].weight;
            break;
        }
    }
    if (weight)
        *weight = styleWeight;
    if (lineSpacing)
        *lineSpacing = 0;
    return size;
}

CGFloat CTFontGetAccessibilityBoldWeightOfWeight(CGFloat weight) { return fmin(1, weight + 0.3); }

bool CTFontGetGlyphsForCharacterRange(CTFontRef font, CGGlyph glyphs[], CFRange range)
{
    bool all = true;
    for (CFIndex i = 0; i < range.length; i++) {
        UTF32Char c = (UTF32Char)(range.location + i);
        UniChar units[2];
        CGGlyph pair[2] = { 0, 0 };
        CFIndex n = 1;
        if (c > 0xFFFF) {
            units[0] = 0xD800 + ((c - 0x10000) >> 10);
            units[1] = 0xDC00 + ((c - 0x10000) & 0x3FF);
            n = 2;
        } else
            units[0] = (UniChar)c;
        if (!CTFontGetGlyphsForCharacters(font, units, pair, n))
            all = false;
        glyphs[i] = pair[0];
    }
    return all;
}

CTFontSymbolicTraits CTFontGetPhysicalSymbolicTraits(CTFontRef font) { return CTFontGetSymbolicTraits(font); }

CFBitVectorRef CTFontCopyColorGlyphCoverage(CTFontRef font)
{
    if (!CTFontIsAppleColorEmoji(font))
        return NULL;
    CFIndex count = CTFontGetGlyphCount(font);
    CFMutableBitVectorRef coverage = CFBitVectorCreateMutable(NULL, count);
    CFBitVectorSetCount(coverage, count);
    CFBitVectorSetAllBits(coverage, 1);
    return coverage;
}

CFBitVectorRef CTFontCopyGlyphCoverageForFeature(CTFontRef font, CFDictionaryRef feature) { return NULL; }
CGFloat CTFontGetSbixImageSizeForGlyphAndContentsScale(CTFontRef font, CGGlyph glyph, CGFloat contentsScale) { return 0; }
uint32_t CTFontGetUIFontType(CTFontRef font) { return UINT32_MAX; } // SystemUIFontTypeNone

bool CTFontHasTable(CTFontRef font, CTFontTableTag tag)
{
    CFArrayRef tables = CTFontCopyAvailableTables(font, kCTFontTableOptionNoOptions);
    if (!tables)
        return false;
    bool found = false;
    for (CFIndex i = 0, count = CFArrayGetCount(tables); i < count && !found; i++)
        found = (CTFontTableTag)(uintptr_t)CFArrayGetValueAtIndex(tables, i) == tag;
    CFRelease(tables);
    return found;
}

// iOS 8 UI fonts are the dot-prefixed ones (.HelveticaNeueInterface-*).
bool CTFontIsSystemUIFont(CTFontRef font)
{
    CFStringRef name = CTFontCopyPostScriptName(font);
    bool result = name && CFStringHasPrefix(name, CFSTR("."));
    if (name)
        CFRelease(name);
    return result;
}

#if __IPHONE_OS_VERSION_MIN_REQUIRED < 100000
CFArrayRef CTFontManagerCopyAvailableFontFamilyNames(void)
{
    CFMutableSetRef seen = CFSetCreateMutable(NULL, 0, &kCFTypeSetCallBacks);
    CFMutableArrayRef families = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CTFontCollectionRef collection = CTFontCollectionCreateFromAvailableFonts(NULL);
    CFArrayRef descriptors = collection ? CTFontCollectionCreateMatchingFontDescriptors(collection) : NULL;
    for (CFIndex i = 0, count = descriptors ? CFArrayGetCount(descriptors) : 0; i < count; i++) {
        CFStringRef family = CTFontDescriptorCopyAttribute(CFArrayGetValueAtIndex(descriptors, i), kCTFontFamilyNameAttribute);
        if (!family)
            continue;
        if (!CFSetContainsValue(seen, family)) {
            CFSetAddValue(seen, family);
            CFArrayAppendValue(families, family);
        }
        CFRelease(family);
    }
    CFArraySortValues(families, CFRangeMake(0, CFArrayGetCount(families)), (CFComparatorFunction)CFStringCompare, NULL);
    if (descriptors)
        CFRelease(descriptors);
    if (collection)
        CFRelease(collection);
    CFRelease(seen);
    return families;
}
#endif

void CTParagraphStyleSetCompositionLanguage(CTParagraphStyleRef style, uint32_t language) { }

// MARK: - MobileGestalt

// iOS 8 MobileGestalt aborts the process on questions it does not know
// (HasExtendedColorDisplay, DeviceCornerRadius, the hashed keys...). Only the
// questions it answers are forwarded; the rest get the caller's default.
static bool mobileGestaltKnows(CFStringRef question)
{
    static const char* const known[] = {
        "apple-internal-install", "main-screen-class", "main-screen-pitch", "main-screen-scale",
        "ipad", "DeviceName", "DeviceClassNumber", "bluetooth", "wapi", NULL,
    };
    char name[64];
    if (!question || !CFStringGetCString(question, name, sizeof(name), kCFStringEncodingUTF8))
        return false;
    for (int i = 0; known[i]; i++) {
        if (!strcmp(name, known[i]))
            return true;
    }
    return false;
}

// dlsym(RTLD_DEFAULT) finds libMobileGestalt's exports, not these hidden copies.
#define REAL_MG(type, name, ...) ((type (*)(__VA_ARGS__))dlsym(RTLD_DEFAULT, name))

bool MGGetBoolAnswer(CFStringRef question)
{
    return mobileGestaltKnows(question) && REAL_MG(bool, "MGGetBoolAnswer", CFStringRef)(question);
}

int32_t MGGetSInt32Answer(CFStringRef question, int32_t defaultValue)
{
    return mobileGestaltKnows(question) ? REAL_MG(int32_t, "MGGetSInt32Answer", CFStringRef, int32_t)(question, defaultValue) : defaultValue;
}

float MGGetFloat32Answer(CFStringRef question, float defaultValue)
{
    return mobileGestaltKnows(question) ? REAL_MG(float, "MGGetFloat32Answer", CFStringRef, float)(question, defaultValue) : defaultValue;
}

CFTypeRef MGCopyAnswer(CFStringRef question, CFDictionaryRef options)
{
    return mobileGestaltKnows(question) ? REAL_MG(CFTypeRef, "MGCopyAnswer", CFStringRef, CFDictionaryRef)(question, options) : NULL;
}

#endif
