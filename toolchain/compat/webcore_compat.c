// Private-framework entry points and constants WebCore references that iOS 8-10
// does not have, plus the half-float compiler-rt builtins (no Darwin compiler-rt
// here). Linked hidden into WebCore, so nothing here shadows a system symbol.

#include <CoreFoundation/CoreFoundation.h>
#include <stdint.h>
#include <string.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED) && __IPHONE_OS_VERSION_MIN_REQUIRED < 110000

// GraphicsServices: font cache purging on memory pressure; nothing to purge.
void GSFontPurgeFontCache(void) { }

// FontParser (newer than iOS 10): on NULL, WebCore (WK26_IOS_TARGET) hands the
// font data to CoreText directly.
CFArrayRef FPFontCreateFontsFromData(CFDataRef data) { return NULL; }
CFDataRef FPFontCopySFNTData(const void* font) { return NULL; }

// IOSurface property keys added after iOS 10; older IOSurface ignores unknown keys.
const CFStringRef kIOSurfaceName = CFSTR("IOSurfaceName");
const CFStringRef kIOSurfaceAcceleratorUnwireSurfaceKey = CFSTR("IOSurfaceAcceleratorUnwireSurfaceKey");

#endif

// IEEE half <-> single conversions (compiler-rt __extendhfsf2 / __truncsfhf2).
float __extendhfsf2(uint16_t h)
{
    uint32_t sign = (uint32_t)(h & 0x8000) << 16;
    uint32_t exponent = (h >> 10) & 0x1f;
    uint32_t mantissa = h & 0x3ff;
    uint32_t bits;
    if (!exponent) {
        if (!mantissa)
            bits = sign;
        else { // subnormal half -> normal float
            exponent = 127 - 15 + 1;
            while (!(mantissa & 0x400)) {
                mantissa <<= 1;
                exponent--;
            }
            bits = sign | (exponent << 23) | ((mantissa & 0x3ff) << 13);
        }
    } else if (exponent == 0x1f)
        bits = sign | 0x7f800000 | (mantissa << 13);
    else
        bits = sign | ((exponent + 127 - 15) << 23) | (mantissa << 13);
    float f;
    memcpy(&f, &bits, sizeof(f));
    return f;
}

uint16_t __truncsfhf2(float f)
{
    uint32_t bits;
    memcpy(&bits, &f, sizeof(bits));
    uint16_t sign = (bits >> 16) & 0x8000;
    uint32_t exponent = (bits >> 23) & 0xff;
    uint32_t mantissa = bits & 0x7fffff;
    if (exponent == 0xff) // Inf / NaN (keep NaN quiet and non-zero)
        return sign | 0x7c00 | (mantissa ? 0x200 | (mantissa >> 13) : 0);
    int32_t e = (int32_t)exponent - 127 + 15;
    if (e >= 0x1f)
        return sign | 0x7c00;
    if (e <= 0) { // subnormal or zero half, round to nearest even
        if (e < -10)
            return sign;
        mantissa |= 0x800000;
        uint32_t shift = (uint32_t)(14 - e);
        uint32_t half = mantissa >> shift;
        uint32_t rest = mantissa & ((1u << shift) - 1);
        uint32_t midpoint = 1u << (shift - 1);
        if (rest > midpoint || (rest == midpoint && (half & 1)))
            half++;
        return sign | (uint16_t)half;
    }
    uint32_t half = ((uint32_t)e << 10) | (mantissa >> 13);
    uint32_t rest = mantissa & 0x1fff;
    if (rest > 0x1000 || (rest == 0x1000 && (half & 1)))
        half++; // may carry into the exponent, which is the correct rounding
    return sign | (uint16_t)half;
}
