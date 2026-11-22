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

`toolchain/check-undefs.py <sdk> <macho>` lists undefined symbols the SDK's .tbd
files do not export. For armv7 the 9.3 SDK is newer than the iOS 8.4.1 devices, so
a clean result there is necessary but not sufficient.

```sh
toolchain/build-libcxx.sh arm64 10.0 iPhoneOS10.3 && toolchain/build-compat.sh arm64 10.0 iPhoneOS10.3
toolchain/build-libcxx.sh armv7 8.0  iPhoneOS9.3  && toolchain/build-compat.sh armv7 8.0  iPhoneOS9.3
```
