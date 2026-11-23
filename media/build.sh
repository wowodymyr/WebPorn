#!/bin/bash
# Build libWebPornMedia.dylib (wpmedia.h over libVLC) for armv7 iOS 8 and install
# it with MobileVLCKit (toolchain/prepare-vlc.sh) in /var/webporn/lib.
#   media/build.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
VLC=$WP/prebuilt/armv7-ios8/vlc/MobileVLCKit.framework
B=$WP/build/media
mkdir -p "$B"
# Compile with ARC, link without it: clang would want libarclite, which the
# open-source toolchain lacks (as in tests/wptest/build.sh).
clang -target armv7-apple-ios8.4 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O2 -Wall -fobjc-arc -fvisibility=default \
    -I"$VLC/Headers" -c "$WP/media/wpmedia.m" -o "$B/wpmedia.o"
clang -target armv7-apple-ios8.4 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" -dynamiclib \
    -install_name /var/webporn/lib/libWebPornMedia.dylib -exported_symbols_list "$WP/media/exports.txt" \
    -framework UIKit -framework QuartzCore -framework Foundation "$VLC/MobileVLCKit" "$B/wpmedia.o" \
    -o "$B/libWebPornMedia.dylib" 2>&1 | grep -v "built for iOS Simulator" || true
[ "${INSTALL:-1}" = 1 ] || exit 0
scp -q "$B/libWebPornMedia.dylib" "$HOST:/var/webporn/lib/libWebPornMedia.dylib.new"
ssh "$HOST" 'cd /var/webporn/lib && ldid -S libWebPornMedia.dylib.new && mv -f libWebPornMedia.dylib.new libWebPornMedia.dylib'
echo "installed libWebPornMedia on $HOST"
