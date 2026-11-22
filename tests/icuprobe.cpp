// Checks the bundled ICU (libwpicu) on the device: version, collation,
// word breaking, regex and case mapping with a non-root locale.

#include <cstdio>
#include <unicode/ubrk.h>
#include <unicode/ucol.h>
#include <unicode/uregex.h>
#include <unicode/ustring.h>
#include <unicode/uversion.h>

int main()
{
    UVersionInfo v;
    char version[U_MAX_VERSION_STRING_LENGTH];
    u_getVersion(v);
    u_versionToString(v, version);
    std::printf("ICU %s\n", version);

    UErrorCode status = U_ZERO_ERROR;
    UCollator* coll = ucol_open("ru", &status);
    UChar a[16], b[16];
    u_strFromUTF8(a, 16, nullptr, "ёж", -1, &status);
    u_strFromUTF8(b, 16, nullptr, "жук", -1, &status);
    std::printf("collate ru: ёж %s жук (%s)\n", ucol_strcoll(coll, a, -1, b, -1) == UCOL_LESS ? "<" : ">=", u_errorName(status));
    ucol_close(coll);

    UChar text[64];
    int32_t len;
    status = U_ZERO_ERROR;
    u_strFromUTF8(text, 64, &len, "Привет, мир! Hello world.", -1, &status);
    UBreakIterator* words = ubrk_open(UBRK_WORD, "ru", text, len, &status);
    int count = 0;
    for (int32_t p = ubrk_first(words); p != UBRK_DONE; p = ubrk_next(words))
        count += ubrk_getRuleStatus(words) >= UBRK_WORD_LETTER;
    std::printf("words: %d (%s)\n", count, u_errorName(status));
    ubrk_close(words);

    status = U_ZERO_ERROR;
    URegularExpression* re = uregex_openC("\\p{Script=Cyrillic}+", 0, nullptr, &status);
    uregex_setText(re, text, len, &status);
    int matches = 0;
    while (uregex_findNext(re, &status))
        ++matches;
    std::printf("regex cyrillic runs: %d (%s)\n", matches, u_errorName(status));
    uregex_close(re);

    UChar upper[64];
    char out[128];
    status = U_ZERO_ERROR;
    int32_t ulen = u_strToUpper(upper, 64, text, len, "tr", &status);
    u_strToUTF8(out, sizeof out, nullptr, upper, ulen, &status);
    std::printf("upper: %s (%s)\n", out, u_errorName(status));
    return 0;
}
