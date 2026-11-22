#!/bin/bash
# ICU 74.2 (matches WebKit's Source/WTF/icu headers), unversioned symbols like
# Apple's libicucore, linked into one dylib: /var/webporn/lib/libwpicu.dylib.
#   build-icu.sh <arch> <min> <sdk-name>
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG
B=$WP/build/icu-$TAG
SRC=$WP/src/icu-74.2/source
HOST=$WP/build/icu-host
BIN=$HOME/theos/toolchain/linux/iphone/bin
[ -x "$HOST/bin/genccode" ] || { echo "build the host ICU in $HOST first"; exit 1; }
case $ARCH in arm64) TRIPLE=aarch64-apple-darwin ;; *) TRIPLE=arm-apple-darwin ;; esac

COMMON="-target $ARCH-apple-ios$MIN -isysroot $WP/sdks/$SDK.sdk -isystem $WP/toolchain/sdk-overlay/include -O2"
rm -rf "$B"; mkdir -p "$B"; cd "$B"
CC=clang CXX=clang++ \
CFLAGS="$COMMON" \
CXXFLAGS="$COMMON -std=c++23 -nostdinc++ -isystem $P/libcxx/include/c++/v1 -faligned-allocation -fno-exceptions" \
CPPFLAGS="-DU_CHARSET_IS_UTF8=1 -DUCONFIG_NO_LEGACY_CONVERSION=1" \
LDFLAGS="--ld-path=$BIN/ld" \
AR=/usr/lib/llvm-21/bin/llvm-ar RANLIB=/usr/lib/llvm-21/bin/llvm-ranlib \
"$SRC/configure" --host=$TRIPLE --with-cross-build="$HOST" \
    --enable-static --disable-shared --disable-renaming \
    --disable-tools --disable-tests --disable-samples --disable-extras --disable-icuio --disable-layoutex \
    --with-data-packaging=static --prefix="$P/icu" > configure.log
make -j"$(nproc)" > make.log
make install > install.log

mkdir -p "$P/icu/dylib"
clang++ -target "$ARCH-apple-ios$MIN" -isysroot "$WP/sdks/$SDK.sdk" --ld-path="$BIN/ld" -dynamiclib -nostdlib++ \
    -install_name /var/webporn/lib/libwpicu.dylib -compatibility_version 1 -current_version 74.2 \
    -Wl,-all_load "$P/icu/lib/libicuuc.a" "$P/icu/lib/libicui18n.a" "$P/icu/lib/libicudata.a" \
    "$P/libcxx/lib/libc++.a" -L"$P/compat/lib" -Wl,-hidden-lwpcxxcompat -lc++abi \
    -o "$P/icu/dylib/libwpicu.dylib" 2>&1 | grep -v 'built for iOS Simulator' || true
"$BIN/ldid" -S "$P/icu/dylib/libwpicu.dylib"
ls -la "$P/icu/dylib/libwpicu.dylib"
