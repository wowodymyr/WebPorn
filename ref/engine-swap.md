# How Web Port swaps iOS 6's WebKit for a 2026 one at runtime

Web Port runs Apple's 2026 WebKit (tag `WebKit-7624.5.1.10.3`: JavaScriptCore,
WebCore, WebKitLegacy) inside the stock MobileSafari and WebSheet on iOS 6.1
(armv7). Nothing on the system is modified: no files in `/System` are
replaced, and nothing is patched on disk. The swap happens inside each app's
process, at launch, from a MobileSubstrate tweak.

## The short version: nothing is unloaded

iOS 6's WebKit can't really be unloaded. It lives in the dyld shared cache,
and UIKit (and everything else linked against it) has already bound its
function pointers and class references to it by the time a tweak runs.

So the tweak does something else. It loads the new engine **next to** the old
one, then moves every reference in the process from the old engine to the
new one. The old images stay mapped but orphaned: nothing calls them any
more.

The new frameworks live in `/var/wkd/` and have their own install names
(`/var/wkd/WebCore.framework/WebCore` and so on). Because the names differ from
the system ones, dyld loads them as separate images instead of reusing the
shared-cache copies.

## When it runs

The tweak's constructor does all of this very early, before
`UIApplication` exists and before any WebView is created:

1. **Per-app gate.** The tweak is injected into every UIKit process, so the
   first thing it does is check the bundle ID. Safari and WebSheet are on by
   default; other apps are opt-in (a marker file per app, toggled from a
   Settings pane); SpringBoard is never touched.
2. **Early hooks** that must be in place before the first WebView: font
   mapping, user agent, engine settings, content blocking, and a few tap
   behaviors.
3. **Preflight.** If the old WebKit is already running (the WebThread is
   enabled or exists, or `UIApplication` has already been created), it
   refuses to swap and changes nothing. Swapping an engine that already
   has live objects would be unsafe.
4. **The displacement**, described below.

## The displacement, step by step

### 0. Find the old engine

With `dlopen(..., RTLD_NOLOAD)` it checks which of the three old images are
loaded. The paths differ by iOS version: JavaScriptCore became a public
framework in iOS 7, and on iOS 8 UIWebView's WebKit is `WebKitLegacy`.

### 0b. Silence the old engine's notification observers

iOS 6's WebKit registers `NSNotificationCenter` observers at load time. If they
stayed, notifications posted by the new engine would run 2012 code on 2026
objects. That crashed Safari in practice (in
`_postCacheModelChangedNotification`).

The tweak reads CoreFoundation's internal registration table (with the layout
taken from 6.1.3's CoreFoundation in IDA and validated before use). It finds
the observers whose code lives in the old images, and removes them with the
normal `-[NSNotificationCenter removeObserver:]`, never by writing the table
directly. It also hooks registration, so the orphaned images can't register
new observers later.

### 0c. Set the JIT options

JSC reads its `JSC_*` options from the environment once, when it loads, so
they are set before the `dlopen`: baseline, RegExp and DFG JITs on, FTL off
(FTL's B3/Air backend has no ARM Thumb-2 support).

### 1. Take over the Objective-C class names

This is the key trick. Code everywhere looks up WebKit classes by name
(`objc_getClass("WebView")`, `NSClassFromString`, and so on), and the new
engine defines classes with the same names as the old one.

On iOS 6, `objc_getClass` checks the runtime's own table,
`gdb_objc_realized_classes`, **before** the shared cache's precomputed class
table. So the tweak registers a dyld add-image callback. For every image
loaded from `/var/wkd/`, the callback walks that image's `__objc_classlist`
and calls `NXMapInsert` to put each class into that table under its name.
From then on, every name lookup returns the new class.

It only takes a name when nobody claims it yet or the old engine claims it, so
it never steals an unrelated class. It has to happen in the add-image callback
because the new engine's own initializers look classes up by name as they
run.

### 2. Load the new engine

It `dlopen`s WebKitLegacy, WebCore and JavaScriptCore from `/var/wkd/`, along
with a stubs library (the C/ObjC symbols iOS 6.1 is missing, plus
compatibility shims) and a Safari-side compat library, all with
`RTLD_GLOBAL`. If the process's image count doesn't go up, dyld treated the
new frameworks as the old ones (an install-name collision), and the tweak stops.

### 4. Rebind every pointer into the old engine

Everything already loaded (UIKit, Safari itself, other frameworks) has
resolved pointers into the old engine: lazy and non-lazy symbol pointers, GOT
entries, ObjC class references, superclass references.

For every loaded image, the rebinder parses the `LC_DYLD_INFO` bind,
weak-bind and lazy-bind opcode streams, the same tables dyld used when it
bound the image. A slot is in scope if either:

- its dylib ordinal names one of the old engine images, or
- its current value points into an old image. This catches flat-namespace
  lookups and re-exports.

For each slot in scope, it resolves the symbol by name with `dlsym` on the
new engine's handles. It rejects any answer that lands back in an old image,
then writes the new address into the slot. Writing needs `mprotect`, falling
back to `vm_protect` with `VM_PROT_COPY` for pages mapped from the shared
cache.

Lazy slots are patched right away too. dyld never revisits a lazy slot once
it's bound, and resetting one would make it re-resolve to the old engine.

If any in-scope slot can't be resolved in the new engine, the swap isn't
complete: that call would still go to the old code.

### 4b. Fix the new engine's own flat lookups

The new frameworks are linked with flat-namespace lookups for the symbols
iOS 6 doesn't have. Flat lookup follows load order, and the old engine loaded
first, so without a second pass some of the new engine's calls would land in
the old one. The same rebinder runs again, limited to the `/var/wkd/` images
and their flat-lookup binds.

### Late images

Some frameworks load later (DataDetectorsUI, for example, is loaded lazily by
UIKit). By this point the add-image callback is set up to rebind any image
that loads after the swap and re-attach its categories. Otherwise a
late-loaded image would bind to the old engine and crash on the new engine's
objects.

### 4c. Redirect functions UIKit finds with `dlsym`

From iOS 7, UIKit soft-links a few WebKit entry points (`WebKitInitialize`,
`WebKitSetIsClassic`, the background-task setters) with `dlsym` rather than
binding them, so step 4 never sees them. Those old functions are hooked with
`MSHookFunction` to jump to the new ones.

### 5. Move categories over to the new classes

UIKit and others add their own methods to WebKit classes through categories
(e.g. `-[WebFrame isMainFrame]`). The runtime attached those methods to the
**old** classes at launch, and rebinding the category's class pointer doesn't
move them. So for every foreign category whose class now points at a new
engine class, the tweak adds its methods with `class_addMethod`, as the
runtime's `attachCategories` would have. It only skips methods the class
itself already defines (checking only the class's own methods, not the
superclass's, so a subclass override isn't hidden).

### 5b / 5c. Safari shims and media

- The compat library installs the Safari-side selector shims: the ObjC/UIKit
  methods iOS 6's Safari expects but the 2026 WebKit renamed or removed. This
  runs after step 5 so no method is added twice.
- The media engine loads last. iOS 6's AVFoundation is too old for modern
  WebCore, so `<video>` runs on a libvlc-backed WebCore media player plus a
  native fullscreen player.

### 6. Second observer sweep

A final pass removes any old-engine observers that the registration hook
missed (registered before the hook took effect, or through
`CFNotificationCenterAddObserver`).

## After the swap

The constructor returns and the app continues launching as normal. When UIKit
creates its first `UIWebView`, every class lookup, every bound call and every
category method it touches now goes to the 2026 engine. The 2012 engine is
still in memory but never runs.
