# WebPorn

Modern WebKit (Safari 26, tag `WebKit-7624.5.1.10.3`) for jailbroken iOS 8–10,
swapped in at runtime the way Web Port does it on iOS 6 (see `ref/`).

## Targets

| Device              | Arch  | iOS    | SDK   | Deployment |
|---------------------|-------|--------|-------|------------|
| iPad mini 2         | arm64 | 10.3.3 | 10.3  | 10.0       |
| iPhone 5, iPad 4    | armv7 | 8.4.1  | 9.3   | 8.0        |

## Layout

- `ref/` — Web Port engine diff and the engine-swap writeup (upstream reference, do not edit)
- `src/webkit` — WebKit tag `WebKit-7624.5.1.10.3`, sparse (no LayoutTests/JSTests/PerformanceTests);
  branch `webport` = tag + Web Port diff, branch `webporn` = our work on top
- `src/llvm-project` — LLVM 21.1.8 runtimes (libc++/libc++abi) for the static modern libc++
- `src/tlsfix` — nfzerox/TLSFix (SecureTransport → OpenSSL 1.1.1); OpenSSL not vendored, build it
- `sdks/` — iPhoneOS10.3.sdk and iPhoneOS9.3.sdk from theos/sdks (sparse clone in `sdks/theos-sdks`)
- `toolchain/` — CMake toolchain files and wrappers
- `prebuilt/` — per-arch libc++, ICU, WOFF2, OpenSSL, libvlc
- `tweak/` — engine-swap tweak, stubs library, Safari/UIKit compat
- `docs/` — notes

## Toolchain

Builds run inside the `ubuntu` toolbox (Ubuntu 26.04).

- compiler: system clang 21 (`/usr/bin/clang`), `-target <arch>-apple-ios<min>`
- linker: ld64-609 from Theos (`~/theos/toolchain/linux/iphone/bin/ld`), armv7/armv7s/arm64
- signing: `ldid` from the same Theos toolchain
- archives: `llvm-ar`/`llvm-ranlib` (cctools `ar` wants triple-prefixed ranlib)
- old-SDK header fixes: `toolchain/sdk-overlay/include` (first `-isystem`, set by `ios.cmake`)
- SDK fixes we made locally: `sdks/LOCAL-CHANGES.md`

## Runtime support libraries (per target, in `prebuilt/<arch>-ios<N>/`)

- `libcxx/` — LLVM 21 libc++, static and hermetic, ABI namespace `std::__wp` so it
  never collides with the system `std::__1` already loaded in the process; uses the
  system `libc++abi.dylib`. Build: `toolchain/build-libcxx.sh <arch> <min> <sdk>`.
- `compat/lib/libwpcxxcompat.a` — sized/aligned `operator new/delete` (iOS 11+ in
  libc++abi) and `clock_gettime` (iOS 10+). Link with `-Wl,-hidden-lwpcxxcompat`.
  Build: `toolchain/build-compat.sh <arch> <min> <sdk>`.

- `icu/dylib/libwpicu.dylib` — ICU 74.2 (same version as WebKit's `Source/WTF/icu`
  headers), unversioned symbols, installed on device as `/var/webporn/lib/libwpicu.dylib`.
  Build (needs the host ICU in `build/icu-host`): `toolchain/build-icu.sh`.
- `woff2/lib/libwpwoff2.a` — decode-only woff2 1.0.2 + brotli 1.1.0. Build: `toolchain/build-woff2.sh`.

## WebKit

`toolchain/configure-webkit.sh <arch> <min> <sdk> [cmake args]` configures
`src/webkit` into `build/webkit-<arch>-ios<N>` (CMake Mac port, `WK_IOS_TARGET=ON`,
fatal warnings off — the Web Port diff is not -Werror clean). Build WebKit against a
new SDK, as Web Port did (iPhoneOS16.5 for armv7); the prebuilt runtimes stay on 9.3/10.3.

JSC-only (works on the iPhone 5, JIT + DFG):

```sh
toolchain/configure-webkit.sh armv7 8.0 iPhoneOS16.5 -DENABLE_WEBCORE=OFF \
    -DENABLE_WEBKIT_LEGACY=OFF -DENABLE_WEBKIT=OFF -DDEVELOPER_MODE=ON \
    -DENABLE_XSLT=OFF -DENABLE_WEBGL=OFF -DENABLE_WEB_RTC=OFF
ninja -C build/webkit-armv7-ios8 jsc
device/deploy-jsc.sh armv7-ios8 iphone
```

What the `webporn` branch adds on top of the Web Port diff:
- armv7 iOS gets JIT/DFG + bmalloc (`WebKitFeatures.cmake`), no WebAssembly
- `WK26_IOS_TARGET` / `WK26_ENGINE_DIAG` defined, the diff's missing `WK26_DATALOG`/
  `WK26_WTFLOG`/`WK26_ENGINE_FLAG` stubbed out (`OptionsMac.cmake`)
- offlineasm ARM: LLInt label addresses and label differences via inline `.long`
  literals (Darwin `.indirect_symbol` needs non-local symbols; LLVM limits movw/movt
  addends to 16 bits)
- memory pressure source falls back to the pre-iOS 10 flag mask
- `libwpcxxcompat.a` is linked hidden into every image (`WEBPORN_COMPAT_A`); it also
  carries iOS 10 libSystem calls (`os_log`, `mach_continuous_time`, `mkostemp`, dyld SPI)

## Device

Engine files go to `/var/webporn/` (iPhone 5 root fs has ~565 MB free).
`device/<name>/exports.tsv` is the export list of that device's shared cache
(`toolchain/dsc-exports.py`); pass it to `check-undefs.py` instead of an SDK.
SSH host alias `iphone` (iPhone 5, iOS 8.4.1) is in `~/.ssh/config`.

- JIT needs the `dynamic-codesigning` entitlement (`device/entitlements/jsc.xml`). iOS 8
  kills binaries whose entitlements were signed by the host ldid, so `deploy-jsc.sh`
  signs `jsc` with the device's own ldid.
- No debugger on the phone: `tests/crashprobe.c` built as a dylib and loaded with
  `DYLD_INSERT_LIBRARIES` prints registers and a symbolized backtrace on a crash.

`toolchain/check-undefs.py <sdk> <macho>` lists undefined symbols the SDK's .tbd
files do not export. For armv7 the 9.3 SDK is newer than the iOS 8.4.1 devices, so
a clean result there is necessary but not sufficient.

With the device's `exports.tsv` plus our own JSC/WebCore exports and `prebuilt/<tag>/stubs`
it is exact: WebCore and WebKitLegacy for armv7-ios8 have 0 unresolved symbols
(`device/iphone5-8.4.1/missing-*.txt`). The 105 newer CoreText/CG/CommonCrypto/Security
entry points are implemented in `toolchain/compat/webcore_ios8_compat.{c,m}` (older API
where one exists — CTFontTransformGlyphs for shaping, CTFontCreateForStringWithLanguage
for fallback, HKDF over CCHmac, conic gradients drawn as wedges — otherwise failing the
way the WK26 call sites expect); iOS 10 libSystem calls are in `system_compat.c`. The
compat archive is not a ninja dependency: after rebuilding it, delete the WebCore and
WebKitLegacy binaries to force a relink.

`toolchain/objc-selector-audit.py <cache> <macho>...` lists selectors the Mach-Os send
that no class or category in the shared cache implements — unrecognized-selector
crashes the linker cannot see. The phone's cache copy was taken from memory and has
some pointers slid by 0x3a74000; the script copes. Result for armv7-ios8:
`device/iphone5-8.4.1/missing-selectors.tsv` (lib, selector, source files), still to be
triaged; many are behind respondsToSelector:, informal protocols, or media/PiP code that
is unreachable without the iOS 9+ classes. Shimmed so far (runtime class_addMethod in
webcore_ios8_compat.m): -[NSHTTPCookie sameSitePolicy], -[NSProcessInfo
isLowPowerModeEnabled/thermalState].

```sh
toolchain/build-libcxx.sh arm64 10.0 iPhoneOS10.3 && toolchain/build-compat.sh arm64 10.0 iPhoneOS10.3
toolchain/build-libcxx.sh armv7 8.0  iPhoneOS9.3  && toolchain/build-compat.sh armv7 8.0  iPhoneOS9.3
```

## Running the engine on the device (armv7, iPhone 5 / iOS 8.4.1)

Status 2026-11-23: a stock UIWebView app (`tests/wptest`) runs WebPorn after the
in-process engine swap; modern sites (en.m.wikipedia.org) load over TLSFix.
Screenshots: `device/iphone5-8.4.1/results/`.

```sh
device/deploy-webkit.sh armv7-ios8 iphone   # JSC + WebCore + WebKitLegacy -> /var/webporn/lib
tweak/build.sh                             # WebPornSwap.dylib (Substrate, filter: net.webporn.wptest)
tweak/build-tlsfix.sh                      # TLSFix + OpenSSL 1.1.1w (toolchain/build-openssl.sh), same filter
tests/wptest/build.sh                      # WPTest.app; `uiopen wptest:` on the device
device/last-crash.py WPTest                # newest crash report, WebPorn frames symbolized
```

WPTest loads `/var/mobile/Media/webporn/url.txt` (or `test.html`) and writes
`result.txt` (JS probes), `screenshot.png` and `error.txt` there. Headless tests
without UIKit: `tests/webview-smoke.m` (WebView + JS + PNG via `_drawRect:`),
`tests/dlopen-test.c` (RTLD_NOW load of each framework).

`tweak/WebPornSwap.m` follows ref/engine-swap.md on iOS 8: class names via
NXMapInsert into gdb_objc_realized_classes; dlopen; rebind every bind / weak / lazy
slot into the old images (only UIKit has any at launch, 101; DataDetectorsUI,
CorePDF and QuickLook load later and are rebound from the add-image callback);
dlsym hooked instead of individual soft-linked functions; UIKit's ~40 categories on
DOM/WebFrame classes re-attached. `/var/webporn/swap-dryrun` = log only
(`/var/mobile/Media/webporn/swap.log`). Lookups use RTLD_FIRST handles: a plain
handle also searches the image's dependencies, which include the old engine via UIKit.

Gotchas found on the way:
- iOS 8 `class_copyMethodList` / `class_addMethod` do not realize the class; call
  `class_respondsToSelector` first. 32-bit `class_t.bits` data mask is `~3`.
- Unrecognized selectors are the main runtime failure. `toolchain/objc-selector-audit.py
  device/iphone5-8.4.1/selectors.txt <machos>` lists selectors no iOS 8 class implements
  (`selectors.txt` is ground truth from `tests/objc-methods.m` run on the phone), but
  it cannot see class/receiver mismatches (`+[UIApplication _classicMode]` exists only as
  an instance method; `CADisplayLink.preferredFramesPerSecond` is implemented by other
  classes). An ObjC exception that unwinds through WebCore's -fno-exceptions frames
  leaves locks held: a hang (DisplayRefreshMonitor), not a crash. Shims:
  `toolchain/compat/webcore_ios8_compat.m` (table applied per loaded image).
- iOS 8 MobileGestalt aborts on unknown questions; WebCore's MG calls go through
  allowlisting wrappers in webcore_ios8_compat.c.
- Overwriting a signed binary in place on iOS 8 gets the next exec SIGKILLed; copy to
  a new name and `mv`.
- `killall -SEGV <app>` makes CrashReporter write all thread stacks of a hung app.
- uutils `sort -u` (coreutils 0.8.0 here) silently drops lines; dedupe with Python.
- Hard soft-links (`SOFT_LINK*` without OPTIONAL / MAY_FAIL) RELEASE_ASSERT when the OS
  lacks the symbol. `toolchain/softlink-audit.py device/iphone5-8.4.1/exports.tsv src/webkit
  <machos>` lists the ones linked into our binaries (names come from the
  `__TEXT,__dlsym_cstr` / `__getClass_cstr` sections) that iOS 8 cannot satisfy: 171
  (CoreMedia 81, AVFoundation 27, UIFoundation 23, MediaRemote, OTSVG, DataDetectors...).
  For WK26_IOS_TARGET C++ sources, `WTF/wtf/cocoa/SoftLinking.h` now degrades a missing
  framework / function / constant / pointer / class to a logged no-op returning zero
  (`WTF::softLinkStub`, `softLinkZero`) instead of crashing (MediaRemote's
  MRMediaRemoteSetSupportedCommands crashed bbc.com).
- The AVFoundation media engine does not work on iOS 8 (`createAVAssetForURL` puts
  AVURLAsset option keys that are nil there into a dictionary, uses resourceLoader SPI
  from later releases: bbc.com threw). Until libWebPornMedia exists the tweak turns it
  off by putting `WebKitAVFoundationEnabled = NO` into the NSUserDefaults argument
  domain (no `<video>` engine at all); `/var/webporn/use-avfoundation` keeps it on.
- MobileSafari: iOS 8 Safari still ships its WebKit1 implementation (`BrowserControllerWK1`,
  `TabDocumentWK1`, `LoadingControllerWK1`, `HistoryWK1`, `ReaderContextWK1`), selected by the
  `UseLegacyWebKit` default, so the in-process swap covers it; no WKWebView shim needed.
  `tweak/WebPornSafari.m` (`NAME=WebPornSafari tweak/build.sh`) sets that default in the
  argument domain and answers selectors no class implements any more on Safari's own classes
  with nil (logged to `safari.log`; only `-[BrowserControllerWK1 _updateReaderBackgroundViewFrame]`
  so far); `/var/webporn/safari-trace` traces every WebView delegate call of the WK1 controllers.
  Which apps get the engine: Settings > WebPorn (`tweak/prefs/WebPorn.plist`, an AppList
  page of switches, installed by `tweak/build.sh`) writes `Enabled-<bundle id>` to
  `/var/mobile/Library/Preferences/net.webporn.swap.plist`; WebPornSwap loads into every
  UIKit app and acts only where switched on (WPTest defaults to on), dlopening TLSFix
  (`/var/webporn/lib/tlsfix.dylib`, no longer a tweak of its own) first. WebPornSafari only
  acts when Safari is on. Not yet tried in an App Store app (container sandbox).
  `tests/safari/sites.sh`: 10/10 sites load and render (screens via VNC, `tests/vnc.sh`,
  Veency; vncdotool in `build/vncpkgs`).
  Fixes it needed, in WebPornSwap (they apply to every swapped app):
  - engine SPI shims: `toolchain/engine-spi-audit.py <cache> <new machos> -- <consumers>` lists
    selectors UIKit / WebUI / MobileSafari send that only the old engine implements, with the
    old classes (16: WebHistoryItem transient properties, WebPreferences `_setLayoutInterval:`,
    WAKWindow freeze -> willRotate / didRotate, WebEvent key init with `characterSet:`, ...).
  - old `WTF::callOnMainThread(void(*)(void*), void*)`: Safari and WebUI bind it from the old
    JavaScriptCore, whose main-thread caller was never initialized, so calls were dropped
    (Safari's async policy answer for a new host: cross-host redirects stalled). Hooked to the
    main queue, taking the new engine's WebThreadLock first (Timer asserts otherwise).
  Tools: `tests/exclog` (ExcLog tweak: every ObjC throw + uncaught exceptions to
  `exc-<process>.log`), `toolchain/objc-symbolize.py`, `toolchain/objc-classes.py`.
- Media engine (`<video>` / `<audio>` on libVLC): `media/wpmedia.h` is a C ABI;
  `media/wpmedia.m` -> `/var/webporn/lib/libWebPornMedia.dylib` (`media/build.sh`) implements it
  over MobileVLCKit's libvlc; WebCore's `platform/graphics/webporn/MediaPlayerPrivateWebPorn.mm`
  dlopens it and registers (as the HolePunch engine identity, unused in this build) only when it
  loads. Video uses libVLC's own iOS output (VideoToolbox, OpenGL ES view) inside a CALayer that
  is the engine's platform layer: H.264 720p/1080p30, VP8/VP9 720p in real time on the A6
  (`tests/vlcview`: VLCView app, `run.sh <url>`; `vlc-mode.txt` = wpmedia drives the library).
  Details that matter: preroll (open muted and playing, pause back at 0 once the video output
  exists: setting it up takes ~2.5 s, and with `:start-paused` it only starts on play);
  `:play-and-pause` (keep the output at the end; an unrequested pause at the end = ENDED);
  `:demux=avformat,any` for mp4 (libVLC's mp4 demuxer froze the clock at 0.25 s on a
  video-only file with an edit list); views created asynchronously on the main thread and stop
  on a background queue (the WebThread may hold the web lock while the main thread waits).
  WebCore: video always plays inline on WK26 (`requiresFullscreenForVideoPlayback` false,
  `enterFullscreen` refused without player support): the WebKit1 fullscreen path needs iOS 13
  AVKit (`-[UIWindow windowScene]`). `tests/media/video.html` logs the media events (WPTest,
  `capture-delay.txt`); Safari plays after a tap. VNC (Veency) shows the libVLC GL layer full
  screen; the real screen / in-app capture is right. Known: control icons missing (square play
  glyph), seek requested before preroll lands late, `paint()` empty (canvas drawImage(video)), no MSE.
  Media bytes come from WebCore's loader (ABI 3 stream input: `wpmedia_open_stream` /
  `stream_data` / `stream_request` over `libvlc_media_new_callbacks`): cookies, CORS, blob: and
  data: URLs work. libVLC reads from an 8 MB window (1 MB kept behind); a seek outside it makes
  the library ask for a new HTTP range (a new generation; stale data is dropped). HLS and file:
  still go to libVLC by URL, and so does everything with `/var/webporn/media-direct`.
  Tests: `tests/media/stream.html` (`#<url>`, `#blob`), `tests/media/cookie.html`
  (`tests/serve.py` serves `/private/` only with the cookie `wp=1`).
- libVLC: `toolchain/prepare-vlc.sh armv7 armv7-ios8` thins MobileVLCKit 3.5.1 (libvlc
  3.0.18, last release for iOS 8.4; dylib, all newer imports weak) into
  `prebuilt/armv7-ios8/vlc`, install name `/var/webporn/lib/MobileVLCKit.framework/MobileVLCKit`.
  `tests/vlc-smoke.c` plays a URL into a vmem buffer and prints fps / libvlc stats.
  On the iPhone 5: VideoToolbox H.264 720p60, VP8/VP9 360p60 decode in real time, but the
  vmem path (CVPX copy + chroma conversion, swscale has no NEON bgra path) shows only
  ~16-27 fps, 720p->RV32 5 fps: frames must stay on the GPU (VLC's GLES2 vout).
  VLC's https goes through SecureTransport: fails on iOS 8 roots without TLSFix in the
  process (`DYLD_INSERT_LIBRARIES=.../tlsfix.dylib` for the CLI).
- Images iOS 8's ImageIO cannot decode go through WebCore's own ScalableImageDecoder:
  WebP over libwebp (`toolchain/build-libwebp.sh`, `WEBPORN_WEBP_DIR`) and AVIF over
  dav1d 1.4.3 + decode-only libavif 1.1.1 (`toolchain/build-avif.sh armv7 8.0 iPhoneOS9.3`,
  `WEBPORN_AVIF_DIR`, `USE_AVIF` on for `WK_IOS_TARGET`; 8/10/12-bit, alpha). AVIF is
  recognized by the ftyp brand but not advertised (no `image/avif` in Accept or the MIME
  registry, `<picture>` skips avif sources): a 1280x960 AVIF takes ~190 ms (8-bit) / ~300 ms
  (12-bit) to decode on the A6, so the JPEG/WebP fallbacks win. `tests/images/images.html`
  (served by `tests/serve.py`) shows load and decode times.
- JIT inside an app needs the `dynamic-codesigning` entitlement (WPTest is signed with
  `device/entitlements/jsc.xml` on the device); without it JSC silently runs on LLInt
  (fib(27) 241 ms vs 161 ms).
