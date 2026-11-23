// WebPornSwap: load the WebPorn engine (/var/webporn/lib) next to the system
// WebKitLegacy / WebCore / JavaScriptCore inside a UIKit app and move every
// reference from the old engine to the new one, following Web Port's design
// (ref/engine-swap.md):
//   1. take over the ObjC class names (NXMapInsert into gdb_objc_realized_classes)
//   2. dlopen the new engine
//   3. rebind every bind / lazy-bind / weak-bind slot that points into the old engine
//   4. redirect dlsym() lookups into the old engine (UIKit soft-links some entry points)
//   5. attach foreign categories of old-engine classes to the new classes
// Loaded into every UIKit app; it only acts in the apps switched on in
// Settings > WebPorn (AppList page, tweak/prefs/WebPorn.plist), and loads TLSFix
// (/var/webporn/lib/tlsfix.dylib) there first.
// With /var/webporn/swap-dryrun present nothing is changed; the log only says
// what would be rebound and what does not resolve. Log: /var/mobile/Media/webporn/swap.log

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define NEW_ROOT "/var/webporn/lib/"
#define LOG_PATH "/var/mobile/Media/webporn/swap.log"

enum { JSCImage, WebCoreImage, WebKitLegacyImage, EngineImageCount };
static const char* const oldPaths[EngineImageCount] = {
    "/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore",
    "/System/Library/PrivateFrameworks/WebCore.framework/WebCore",
    "/System/Library/PrivateFrameworks/WebKitLegacy.framework/WebKitLegacy",
};
static const char* const newPaths[EngineImageCount] = {
    NEW_ROOT "JavaScriptCore.framework/JavaScriptCore",
    NEW_ROOT "WebCore.framework/WebCore",
    NEW_ROOT "WebKitLegacy.framework/WebKitLegacy",
};

// Images that use the system engine's C++ ABI themselves; rebinding half of
// them to the new engine would be worse than leaving them alone.
static const char* const skippedImages[] = {
    "/System/Library/Frameworks/WebKit.framework/WebKit",
    "/System/Library/PrivateFrameworks/WebKit.framework/WebKit",
    NULL,
};

typedef struct {
    uintptr_t start, end;
} Range;

enum { MaxRanges = 64 };
static Range oldRanges[MaxRanges], newRanges[MaxRanges];
static int oldRangeCount, newRangeCount;
static int oldRangeImage[MaxRanges];
static void* oldHandles[EngineImageCount];
static void* newHandles[EngineImageCount];
// RTLD_FIRST handles: dlsym searches only that image. A plain handle also
// searches its dependencies, and through UIKit those include the old engine.
static void* newLookupHandles[EngineImageCount];
static bool dryRun;
static FILE* logFile;
static void* (*realDlsym)(void*, const char*);

static void logf_(const char* format, ...) __attribute__((format(printf, 1, 2)));
static void logf_(const char* format, ...)
{
    if (!logFile)
        return;
    va_list args;
    va_start(args, format);
    vfprintf(logFile, format, args);
    va_end(args);
    fflush(logFile);
}

#ifdef __LP64__
typedef struct mach_header_64 MachHeader;
typedef struct segment_command_64 SegmentCommand;
typedef struct section_64 Section;
#define SEGMENT_CMD LC_SEGMENT_64
#else
typedef struct mach_header MachHeader;
typedef struct segment_command SegmentCommand;
typedef struct section Section;
#define SEGMENT_CMD LC_SEGMENT
#endif

#define FOR_EACH_COMMAND(header, command) \
    for (const struct load_command* command = (const struct load_command*)((const MachHeader*)(header) + 1), *end_ = 0; !end_; end_ = (void*)1) \
        for (uint32_t i_ = 0; i_ < ((const MachHeader*)(header))->ncmds; i_++, command = (const struct load_command*)((const char*)command + command->cmdsize))

static int addRanges(const struct mach_header* header, intptr_t slide, Range* ranges, int count, int* owner, int image)
{
    FOR_EACH_COMMAND(header, command) {
        if (command->cmd != SEGMENT_CMD)
            continue;
        const SegmentCommand* segment = (const SegmentCommand*)command;
        if (!strcmp(segment->segname, SEG_PAGEZERO) || !strcmp(segment->segname, SEG_LINKEDIT) || count >= MaxRanges)
            continue;
        if (owner)
            owner[count] = image;
        ranges[count++] = (Range) { segment->vmaddr + slide, segment->vmaddr + slide + segment->vmsize };
    }
    return count;
}

static int oldImageFor(uintptr_t address)
{
    for (int i = 0; i < oldRangeCount; i++) {
        if (address >= oldRanges[i].start && address < oldRanges[i].end)
            return oldRangeImage[i];
    }
    return -1;
}

static bool inNewEngine(uintptr_t address)
{
    for (int i = 0; i < newRangeCount; i++) {
        if (address >= newRanges[i].start && address < newRanges[i].end)
            return true;
    }
    return false;
}

static bool isNewImage(const char* path) { return path && !strncmp(path, NEW_ROOT, strlen(NEW_ROOT)); }

static int oldImageIndexForPath(const char* path)
{
    for (int i = 0; i < EngineImageCount; i++) {
        if (path && !strcmp(path, oldPaths[i]))
            return i;
    }
    return -1;
}

static const Section* findSection(const struct mach_header* header, const char* segmentName, const char* sectionName)
{
    FOR_EACH_COMMAND(header, command) {
        if (command->cmd != SEGMENT_CMD)
            continue;
        const SegmentCommand* segment = (const SegmentCommand*)command;
        const Section* section = (const Section*)(segment + 1);
        for (uint32_t s = 0; s < segment->nsects; s++) {
            if (!strncmp(section[s].sectname, sectionName, 16) && (!segmentName || !strncmp(section[s].segname, segmentName, 16)))
                return &section[s];
        }
    }
    return NULL;
}

// MARK: - 1. Class names

extern void* gdb_objc_realized_classes;
extern void* NXMapGet(void* table, const void* key);
extern void* NXMapInsert(void* table, const void* key, const void* value);

// The class's name without realizing it: data() is a class_rw_t once realized
// (RW_REALIZED in its flags), the compiler's class_ro_t before.
static const char* rawClassName(Class cls)
{
    uintptr_t bits = ((uintptr_t*)cls)[4];
#ifdef __LP64__
    bits &= ~(uintptr_t)7;
#else
    bits &= ~(uintptr_t)3;
#endif
    const uint32_t* data = (const uint32_t*)bits;
    if (data[0] & (1u << 31))
        data = *(const uint32_t* const*)((const char*)data + 8); // rw->ro
    return *(const char* const*)((const char*)data + 12 + (sizeof(void*) == 8 ? 4 : 0) + sizeof(void*));
}

static int takeClassNames(const struct mach_header* header)
{
    unsigned long size = 0;
    const Section* section = findSection(header, NULL, "__objc_classlist");
    if (!section)
        return 0;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        if (_dyld_get_image_header(i) == header)
            slide = _dyld_get_image_vmaddr_slide(i);
    }
    Class* classes = (Class*)(section->addr + slide);
    size = section->size / sizeof(Class);
    int taken = 0;
    for (unsigned long i = 0; i < size; i++) {
        const char* name = rawClassName(classes[i]);
        Class current = (Class)NXMapGet(gdb_objc_realized_classes, name);
        if (!current)
            current = objc_getClass(name);
        if (current == classes[i])
            continue;
        if (current && oldImageFor((uintptr_t)current) < 0) {
            logf_("class %s: owned outside the old engine, not taken\n", name);
            continue;
        }
        if (!dryRun)
            NXMapInsert(gdb_objc_realized_classes, name, classes[i]);
        taken++;
    }
    return taken;
}

static bool swapped;
static void rebindImage(const struct mach_header* header, intptr_t slide, const char* path, bool onlyStrayPointers);
static void moveCategoriesOfImage(const struct mach_header* header, intptr_t slide, const char* path);
static bool isSkipped(const char* path);

static void addImageCallback(const struct mach_header* header, intptr_t slide)
{
    Dl_info info;
    if (!dladdr(header, &info))
        return;
    if (swapped) {
        // Late images (DataDetectorsUI, loaded lazily by UIKit) bound to the old
        // engine while loading; move them over like the rest.
        if (!isNewImage(info.dli_fname) && oldImageIndexForPath(info.dli_fname) < 0 && !isSkipped(info.dli_fname)) {
            logf_("late image %s\n", info.dli_fname);
            rebindImage(header, slide, info.dli_fname, false);
            moveCategoriesOfImage(header, slide, info.dli_fname);
        }
        return;
    }
    if (!isNewImage(info.dli_fname))
        return;
    newRangeCount = addRanges(header, slide, newRanges, newRangeCount, NULL, 0);
    logf_("new image %s: took %d class names\n", info.dli_fname, takeClassNames(header));
}

// MARK: - 3. Rebinding

// The symbol in the new engine, trying the image that replaces `engine` first:
// symbols moved between the three (WTF lives in JavaScriptCore, the DOM classes
// moved from WebCore to WebKitLegacy).
static void* newEngineSymbol(int engine, const char* name)
{
    void* target = realDlsym(newLookupHandles[engine], name);
    for (int i = EngineImageCount - 1; i >= 0 && !target; i--)
        target = realDlsym(newLookupHandles[i], name);
    return target;
}

static bool writePointer(uintptr_t* slot, uintptr_t value)
{
    if (dryRun)
        return true;
    vm_address_t page = (vm_address_t)slot & ~(vm_address_t)(vm_page_size - 1);
    if (vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ | VM_PROT_WRITE) != KERN_SUCCESS
        && vm_protect(mach_task_self(), page, vm_page_size, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS)
        return false;
    *slot = value;
    return true;
}

typedef struct {
    const char* path;
    int ordinalToEngine[256]; // dylib ordinal -> engine image, or -1
    uintptr_t segments[32];
    int segmentCount;
    intptr_t slide;
    bool onlyStrayPointers; // new engine images: only fix slots that landed in the old engine
    int rebound, unresolved, inScope;
} BindContext;

static uintptr_t readULEB(const uint8_t** p, const uint8_t* end)
{
    uintptr_t result = 0;
    int shift = 0;
    while (*p < end) {
        uint8_t byte = *(*p)++;
        result |= (uintptr_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    return result;
}

static intptr_t readSLEB(const uint8_t** p, const uint8_t* end)
{
    intptr_t result = 0;
    int shift = 0;
    uint8_t byte = 0;
    while (*p < end) {
        byte = *(*p)++;
        result |= (intptr_t)(byte & 0x7f) << shift;
        shift += 7;
        if (!(byte & 0x80))
            break;
    }
    if (shift < (int)(8 * sizeof(intptr_t)) && (byte & 0x40))
        result |= -((intptr_t)1 << shift);
    return result;
}

static void bindSlot(BindContext* context, uintptr_t address, const char* symbol, int ordinal, intptr_t addend)
{
    uintptr_t* slot = (uintptr_t*)address;
    uintptr_t current = *slot;
    int engine = (ordinal > 0 && ordinal < 256 && !context->onlyStrayPointers) ? context->ordinalToEngine[ordinal] : -1;
    if (engine < 0)
        engine = oldImageFor(current - addend);
    if (engine < 0)
        return;
    context->inScope++;

    const char* name = symbol[0] == '_' ? symbol + 1 : symbol;
    void* target = newEngineSymbol(engine, name);
    if (!target) {
        if (context->unresolved++ < 200)
            logf_("  unresolved %s (%s)\n", symbol, oldPaths[engine]);
        return;
    }
    if (writePointer(slot, (uintptr_t)target + addend))
        context->rebound++;
}

static void runBindOpcodes(BindContext* context, const uint8_t* p, const uint8_t* end, bool lazy)
{
    int ordinal = 0, segment = 0;
    uintptr_t offset = 0;
    intptr_t addend = 0;
    const char* symbol = "";
    while (p < end) {
        uint8_t byte = *p++;
        uint8_t immediate = byte & BIND_IMMEDIATE_MASK;
        switch (byte & BIND_OPCODE_MASK) {
        case BIND_OPCODE_DONE:
            if (!lazy)
                return;
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_IMM:
            ordinal = immediate;
            break;
        case BIND_OPCODE_SET_DYLIB_ORDINAL_ULEB:
            ordinal = (int)readULEB(&p, end);
            break;
        case BIND_OPCODE_SET_DYLIB_SPECIAL_IMM:
            ordinal = immediate ? (int)(int8_t)(BIND_OPCODE_MASK | immediate) : 0;
            break;
        case BIND_OPCODE_SET_SYMBOL_TRAILING_FLAGS_IMM:
            symbol = (const char*)p;
            p += strlen(symbol) + 1;
            break;
        case BIND_OPCODE_SET_TYPE_IMM:
            break;
        case BIND_OPCODE_SET_ADDEND_SLEB:
            addend = readSLEB(&p, end);
            break;
        case BIND_OPCODE_SET_SEGMENT_AND_OFFSET_ULEB:
            segment = immediate;
            offset = readULEB(&p, end);
            break;
        case BIND_OPCODE_ADD_ADDR_ULEB:
            offset += readULEB(&p, end);
            break;
        case BIND_OPCODE_DO_BIND:
            if (segment < context->segmentCount)
                bindSlot(context, context->segments[segment] + context->slide + offset, symbol, ordinal, addend);
            offset += sizeof(void*);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_ULEB:
            if (segment < context->segmentCount)
                bindSlot(context, context->segments[segment] + context->slide + offset, symbol, ordinal, addend);
            offset += readULEB(&p, end) + sizeof(void*);
            break;
        case BIND_OPCODE_DO_BIND_ADD_ADDR_IMM_SCALED:
            if (segment < context->segmentCount)
                bindSlot(context, context->segments[segment] + context->slide + offset, symbol, ordinal, addend);
            offset += immediate * sizeof(void*) + sizeof(void*);
            break;
        case BIND_OPCODE_DO_BIND_ULEB_TIMES_SKIPPING_ULEB: {
            uintptr_t count = readULEB(&p, end);
            uintptr_t skip = readULEB(&p, end);
            for (uintptr_t i = 0; i < count; i++) {
                if (segment < context->segmentCount)
                    bindSlot(context, context->segments[segment] + context->slide + offset, symbol, ordinal, addend);
                offset += skip + sizeof(void*);
            }
            break;
        }
        default:
            logf_("  unknown bind opcode 0x%x in %s\n", byte, context->path);
            return;
        }
    }
}

static void rebindImage(const struct mach_header* header, intptr_t slide, const char* path, bool onlyStrayPointers)
{
    BindContext context = { .path = path, .slide = slide, .onlyStrayPointers = onlyStrayPointers };
    memset(context.ordinalToEngine, 0xff, sizeof(context.ordinalToEngine));
    const struct dyld_info_command* dyldInfo = NULL;
    uintptr_t linkeditBase = 0;
    int ordinal = 0;
    FOR_EACH_COMMAND(header, command) {
        switch (command->cmd) {
        case SEGMENT_CMD: {
            const SegmentCommand* segment = (const SegmentCommand*)command;
            if (context.segmentCount < 32)
                context.segments[context.segmentCount++] = segment->vmaddr;
            if (!strcmp(segment->segname, SEG_LINKEDIT))
                linkeditBase = segment->vmaddr + slide - segment->fileoff;
            break;
        }
        case LC_LOAD_DYLIB:
        case LC_LOAD_WEAK_DYLIB:
        case LC_REEXPORT_DYLIB:
        case LC_LOAD_UPWARD_DYLIB: {
            const struct dylib_command* dylib = (const struct dylib_command*)command;
            ordinal++;
            if (ordinal < 256)
                context.ordinalToEngine[ordinal] = oldImageIndexForPath((const char*)command + dylib->dylib.name.offset);
            break;
        }
        case LC_DYLD_INFO:
        case LC_DYLD_INFO_ONLY:
            dyldInfo = (const struct dyld_info_command*)command;
            break;
        }
    }
    if (!dyldInfo || !linkeditBase)
        return;
    const uint8_t* base = (const uint8_t*)linkeditBase;
    if (dyldInfo->bind_size)
        runBindOpcodes(&context, base + dyldInfo->bind_off, base + dyldInfo->bind_off + dyldInfo->bind_size, false);
    if (dyldInfo->weak_bind_size)
        runBindOpcodes(&context, base + dyldInfo->weak_bind_off, base + dyldInfo->weak_bind_off + dyldInfo->weak_bind_size, false);
    if (dyldInfo->lazy_bind_size)
        runBindOpcodes(&context, base + dyldInfo->lazy_bind_off, base + dyldInfo->lazy_bind_off + dyldInfo->lazy_bind_size, true);
    if (context.inScope)
        logf_("rebind %s: %d slots into the old engine, %d rebound, %d unresolved\n", path, context.inScope, context.rebound, context.unresolved);
}

static bool isSkipped(const char* path)
{
    for (int i = 0; skippedImages[i]; i++) {
        if (!strcmp(path, skippedImages[i]))
            return true;
    }
    return false;
}

static void rebindAll(void)
{
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* path = _dyld_get_image_name(i);
        if (!path || oldImageIndexForPath(path) >= 0)
            continue;
        if (isSkipped(path)) {
            logf_("skipping %s\n", path);
            continue;
        }
        rebindImage(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i), path, isNewImage(path));
    }
}

// MARK: - 4. dlsym

static void* swapDlsym(void* handle, const char* symbol)
{
    void* result = realDlsym(handle, symbol);
    int engine = result ? oldImageFor((uintptr_t)result) : -1;
    if (engine < 0)
        return result;
    void* replacement = newEngineSymbol(engine, symbol);
    if (replacement)
        return replacement;
    logf_("dlsym(%s): no replacement in the new engine\n", symbol);
    return result;
}

// MARK: - 5. Categories

typedef struct {
    uint32_t entsizeAndFlags, count;
    struct { SEL name; const char* types; IMP imp; } methods[];
} MethodList;

typedef struct {
    const char* name;
    Class cls;
    const MethodList* instanceMethods;
    const MethodList* classMethods;
} RawCategory;

static bool classDefinesMethod(Class cls, SEL selector)
{
    unsigned count = 0;
    Method* methods = class_copyMethodList(cls, &count);
    bool found = false;
    for (unsigned i = 0; i < count && !found; i++)
        found = method_getName(methods[i]) == selector;
    free(methods);
    return found;
}

static int attachMethods(Class cls, const MethodList* list)
{
    if (!list)
        return 0;
    // class_copyMethodList and class_addMethod assume a realized class (they read
    // class_rw_t); method lookup realizes it without running +initialize.
    class_respondsToSelector(cls, @selector(class));
    int added = 0;
    for (uint32_t i = 0; i < list->count; i++) {
        SEL selector = list->methods[i].name;
        if (classDefinesMethod(cls, selector))
            continue;
        if (!dryRun)
            class_addMethod(cls, selector, list->methods[i].imp, list->methods[i].types);
        added++;
    }
    return added;
}

static void moveCategoriesOfImage(const struct mach_header* header, intptr_t slide, const char* path)
{
    {
        const Section* section = findSection(header, NULL, "__objc_catlist");
        if (!section)
            return;
        const RawCategory* const* categories = (const RawCategory* const*)(section->addr + slide);
        for (unsigned long c = 0; c < section->size / sizeof(void*); c++) {
            const RawCategory* category = categories[c];
            Class cls = category->cls;
            if (!cls)
                continue;
            if (!inNewEngine((uintptr_t)cls)) {
                // The category's class pointer was not rebound (shared-cache images
                // keep no bind for it); look the class up by its new name.
                if (oldImageFor((uintptr_t)cls) < 0)
                    continue;
                Class replacement = objc_getClass(rawClassName(cls));
                if (!replacement || !inNewEngine((uintptr_t)replacement))
                    continue;
                cls = replacement;
            }
            int added = attachMethods(cls, category->instanceMethods) + attachMethods(object_getClass(cls), category->classMethods);
            if (added)
                logf_("category %s(%s) from %s: %d methods\n", class_getName(cls), category->name, path, added);
        }
    }
}

static void moveCategories(void)
{
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char* path = _dyld_get_image_name(i);
        if (!path || isNewImage(path) || oldImageIndexForPath(path) >= 0 || isSkipped(path))
            continue;
        moveCategoriesOfImage(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i), path);
    }
}

// MARK: - Engine SPI shims

// Methods system code (UIKit, WebUI, MobileSafari) sends to the old engine that the
// new one removed or renamed: toolchain/engine-spi-audit.py lists them with the old
// classes that implemented them. Each is added only where the new class lacks it.

static void* const transientPropertiesKey = (void*)&transientPropertiesKey;

static id historyItemTransientProperty(id self, SEL _cmd, NSString* key)
{
    return [objc_getAssociatedObject(self, transientPropertiesKey) objectForKey:key];
}

static void historyItemSetTransientProperty(id self, SEL _cmd, id value, NSString* key)
{
    NSMutableDictionary* properties = objc_getAssociatedObject(self, transientPropertiesKey);
    if (!properties) {
        properties = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, transientPropertiesKey, properties, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (value)
        [properties setObject:value forKey:key];
    else
        [properties removeObjectForKey:key];
}

static id returnNil(id self, SEL _cmd) { return nil; }
static BOOL returnNo(id self, SEL _cmd) { return NO; }
static void doNothing(id self, SEL _cmd) { }
static void doNothingWithArgument(id self, SEL _cmd, id argument) { }
static unsigned long long defaultOriginQuota(id self, SEL _cmd) { return 5 * 1024 * 1024; }

// The old engine dropped the cache by shrinking it to nothing; so do we.
static void webViewClearBackForwardCache(id self, SEL _cmd)
{
    id list = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("backForwardList"));
    NSUInteger size = ((NSUInteger (*)(id, SEL))objc_msgSend)(list, sel_registerName("pageCacheSize"));
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(list, sel_registerName("setPageCacheSize:"), 0);
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(list, sel_registerName("setPageCacheSize:"), size);
}

// -freezeVisibleRect / -unfreezeVisibleRect became -willRotate / -didRotate.
static void wakWindowFreezeVisibleRect(id self, SEL _cmd)
{
    ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("willRotate"));
}

static void wakWindowUnfreezeVisibleRect(id self, SEL _cmd)
{
    ((void (*)(id, SEL))objc_msgSend)(self, sel_registerName("didRotate"));
}

// iOS 8 UIKit builds key events with a trailing characterSet:; the new initializer
// takes an input manager hint instead and finds the character set itself.
static id webEventInitKeyEvent(id self, SEL _cmd, int type, double timeStamp, NSString* characters, NSString* charactersIgnoringModifiers,
    unsigned modifiers, BOOL repeating, unsigned flags, uint16_t keyCode, BOOL tabKey, int characterSet)
{
    SEL initializer = sel_registerName("initWithKeyEventType:timeStamp:characters:charactersIgnoringModifiers:modifiers:isRepeating:withFlags:withInputManagerHint:keyCode:isTabKey:");
    return ((id (*)(id, SEL, int, double, NSString*, NSString*, unsigned, BOOL, unsigned, NSString*, uint16_t, BOOL))objc_msgSend)(
        self, initializer, type, timeStamp, characters, charactersIgnoringModifiers, modifiers, repeating, flags, nil, keyCode, tabKey);
}

static void webViewAddUserStyleSheet(id self, SEL _cmd, NSString* group, id world, NSString* source, NSURL* url, NSArray* whitelist, NSArray* blacklist)
{
    SEL selector = sel_registerName("_addUserStyleSheetToGroup:world:source:url:includeMatchPatternStrings:excludeMatchPatternStrings:injectedFrames:");
    ((void (*)(id, SEL, NSString*, id, NSString*, NSURL*, NSArray*, NSArray*, int))objc_msgSend)(
        self, selector, group, world, source, url, whitelist, blacklist, 0 /* WebInjectInAllFrames */);
}

// iOS 8 UIKit pushes the orientation into the frame; the new engine pulls it from
// the UIKit delegate in -deviceOrientationChanged, which UIKit 8 does not answer.
static void webFrameSendOrientationChangeEvent(id self, SEL _cmd, int orientation)
{
    id webView = ((id (*)(id, SEL))objc_msgSend)(self, sel_registerName("webView"));
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(webView, sel_registerName("_setDeviceOrientation:"), (NSUInteger)orientation);
}

static void addShim(const char* className, bool classMethod, const char* selectorName, IMP implementation, const char* types)
{
    Class cls = objc_getClass(className);
    if (!cls) {
        logf_("shim %s: no class\n", className);
        return;
    }
    if (classMethod)
        cls = object_getClass(cls);
    SEL selector = sel_registerName(selectorName);
    // class_respondsToSelector realizes the class first (iOS 8 class_addMethod does not).
    if (class_respondsToSelector(cls, selector))
        return;
    class_addMethod(cls, selector, implementation, types);
    logf_("shim %c[%s %s]\n", classMethod ? '+' : '-', className, selectorName);
}

static void installEngineShims(void)
{
    addShim("WebHistoryItem", false, "_transientPropertyForKey:", (IMP)historyItemTransientProperty, "@@:@");
    addShim("WebHistoryItem", false, "_setTransientProperty:forKey:", (IMP)historyItemSetTransientProperty, "v@:@@");
    addShim("WebHistoryItem", false, "_bookmarkID", (IMP)returnNil, "@@:");
    addShim("WebHistoryItem", false, "_sharedLinkUniqueIdentifier", (IMP)returnNil, "@@:");
    addShim("WebHistoryItem", false, "_isInPageCache", (IMP)returnNo, "c@:");
    addShim("WebView", false, "_clearBackForwardCache", (IMP)webViewClearBackForwardCache, "v@:");
    addShim("WebView", true, "_addUserStyleSheetToGroup:world:source:url:whitelist:blacklist:", (IMP)webViewAddUserStyleSheet, "v@:@@@@@@");
    addShim("WebPreferences", false, "_setLayoutInterval:", (IMP)doNothingWithArgument, "v@:i");
    addShim("WebHTMLView", false, "_updateControlTints", (IMP)doNothing, "v@:");
    addShim("WAKWindow", false, "freezeVisibleRect", (IMP)wakWindowFreezeVisibleRect, "v@:");
    addShim("WAKWindow", false, "unfreezeVisibleRect", (IMP)wakWindowUnfreezeVisibleRect, "v@:");
    // Application cache is gone upstream: no quota manager, a fixed default quota.
    addShim("WebSecurityOrigin", false, "applicationCacheQuotaManager", (IMP)returnNil, "@@:");
    addShim("WebApplicationCache", true, "defaultOriginQuota", (IMP)defaultOriginQuota, "Q@:");
    addShim("WebEvent", false, "initWithKeyEventType:timeStamp:characters:charactersIgnoringModifiers:modifiers:isRepeating:withFlags:keyCode:isTabKey:characterSet:",
        (IMP)webEventInitKeyEvent, "@@:id@@IcISci");
    addShim("WebFrame", false, "sendOrientationChangeEvent:", (IMP)webFrameSendOrientationChangeEvent, "v@:i");
}

// MARK: - Old WTF

// MobileSafari and WebUI call WTF::callOnMainThread(void (*)(void*), void*) from the
// old JavaScriptCore (the new WTF has no such overload, so the bind stays there).
// The old engine never ran WTF::initializeMainThread, so its main-thread caller
// object is nil and every such call is silently dropped: Safari's asynchronous
// navigation policy answers (Safe Browsing check for a new host) never arrive and
// a cross-host redirect stalls forever. Send them to the main queue instead,
// holding the web thread lock: with the WebThread on, WTF's "main thread" is
// whoever holds it, and the callbacks go straight back into WebCore (Timer
// asserts otherwise). The run loop observer drops the lock after the iteration.
static void (*newWebThreadLock)(void);

static void oldCallOnMainThread(void (*function)(void*), void* context)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (newWebThreadLock)
            newWebThreadLock();
        function(context);
    });
}

static void hookOldWTF(void (*hookFunction)(void*, void*, void**))
{
    void* callOnMainThread = oldHandles[JSCImage] ? realDlsym(oldHandles[JSCImage], "_ZN3WTF16callOnMainThreadEPFvPvES0_") : NULL;
    newWebThreadLock = realDlsym(newLookupHandles[WebCoreImage], "WebThreadLock");
    if (callOnMainThread && hookFunction) {
        void* original;
        hookFunction(callOnMainThread, (void*)oldCallOnMainThread, &original);
    }
    logf_("old WTF::callOnMainThread: %s\n", callOnMainThread && hookFunction ? "redirected to the main queue" : "not hooked");
}

// MARK: - Media

// The AVFoundation media engine needs AVURLAsset option keys and resourceLoader
// SPI that iOS 8 lacks (soft-links now resolve to nil, and -setObject:forKey:nil
// throws: bbc.com). Until libWebPornMedia provides an engine, keep <video> off
// AVFoundation through the WebKitAVFoundationEnabled default, which WebView copies
// into DeprecatedGlobalSettings before the media engine list is built. The
// argument domain beats both the app's defaults and WebPreferences' registered
// ones, and nothing is persisted. /var/webporn/use-avfoundation keeps it on.
static void disableAVFoundationEngine(void)
{
    if (!access("/var/webporn/use-avfoundation", F_OK)) {
        logf_("AVFoundation media engine: left on\n");
        return;
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary* arguments = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy] ?: [NSMutableDictionary dictionary];
    arguments[@"WebKitAVFoundationEnabled"] = @NO;
    [defaults removeVolatileDomainForName:NSArgumentDomain];
    [defaults setVolatileDomain:arguments forName:NSArgumentDomain];
    logf_("AVFoundation media engine: disabled\n");
}

// MARK: - Entry

static bool appEnabled(void)
{
    NSString* bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (!bundleID || [bundleID isEqualToString:@"com.apple.springboard"])
        return false;
    // Settings > WebPorn writes Enabled-<bundle id>; the test app is on unless switched off.
    NSDictionary* settings = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/net.webporn.swap.plist"];
    id enabled = [settings objectForKey:[@"Enabled-" stringByAppendingString:bundleID]];
    if (!enabled)
        return [bundleID isEqualToString:@"net.webporn.wptest"];
    return [enabled boolValue];
}

__attribute__((constructor)) static void webPornSwap(void)
{
    @autoreleasepool {
        if (!appEnabled())
            return;
        logFile = fopen(LOG_PATH, "w");
        dryRun = !access("/var/webporn/swap-dryrun", F_OK);
        logf_("WebPornSwap in %s (pid %d)%s\n", [[[NSBundle mainBundle] bundleIdentifier] UTF8String], getpid(), dryRun ? " DRY RUN" : "");
        realDlsym = dlsym;
        if (!dlopen("/var/webporn/lib/tlsfix.dylib", RTLD_NOW))
            logf_("TLSFix: %s\n", dlerror());

        for (int i = 0; i < EngineImageCount; i++)
            oldHandles[i] = dlopen(oldPaths[i], RTLD_NOLOAD | RTLD_LAZY);
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            int engine = oldImageIndexForPath(_dyld_get_image_name(i));
            if (engine >= 0)
                oldRangeCount = addRanges(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i), oldRanges, oldRangeCount, oldRangeImage, engine);
        }
        logf_("old engine: %d segments (JSC %p, WebCore %p, WebKitLegacy %p)\n", oldRangeCount, oldHandles[0], oldHandles[1], oldHandles[2]);

        bool (*oldWebThreadIsEnabled)(void) = oldHandles[WebCoreImage] ? realDlsym(oldHandles[WebCoreImage], "WebThreadIsEnabled") : NULL;
        if (oldWebThreadIsEnabled && oldWebThreadIsEnabled()) {
            logf_("old WebThread already running; not swapping\n");
            return;
        }

        setenv("JSC_useFTLJIT", "0", 1);
        _dyld_register_func_for_add_image(addImageCallback);
        uint32_t imagesBefore = _dyld_image_count();
        for (int i = 0; i < EngineImageCount; i++) {
            newHandles[i] = dlopen(newPaths[i], RTLD_NOW | RTLD_GLOBAL);
            if (!newHandles[i]) {
                logf_("dlopen %s: %s\n", newPaths[i], dlerror());
                return;
            }
        }
        for (int i = 0; i < EngineImageCount; i++)
            newLookupHandles[i] = dlopen(newPaths[i], RTLD_NOLOAD | RTLD_FIRST | RTLD_NOW);
        if (_dyld_image_count() <= imagesBefore) {
            logf_("new engine did not add images (install-name collision?); stopping\n");
            return;
        }
        logf_("new engine loaded: %u images now\n", _dyld_image_count());

        rebindAll();

        void* substrate = dlopen("/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate", RTLD_LAZY);
        void (*hookFunction)(void*, void*, void**) = substrate ? realDlsym(substrate, "MSHookFunction") : NULL;
        if (hookFunction && !dryRun)
            hookFunction((void*)dlsym, (void*)swapDlsym, (void**)&realDlsym);
        logf_("dlsym hook: %s\n", hookFunction ? (dryRun ? "skipped (dry run)" : "installed") : "no Substrate");
        if (!dryRun)
            hookOldWTF(hookFunction);

        moveCategories();
        installEngineShims();
        disableAVFoundationEngine();
        swapped = true;
        logf_("swap done\n");
    }
}
