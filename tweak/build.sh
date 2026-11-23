#!/bin/bash
# Build WebPornSwap.dylib (armv7, iOS 8) and install it as a Substrate tweak.
#   tweak/build.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
B=$WP/build/tweak
mkdir -p "$B"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O1 -Wall -Wno-unused-function \
    -c "$WP/tweak/WebPornSwap.m" -o "$B/WebPornSwap.o"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" -dynamiclib \
    -install_name /Library/MobileSubstrate/DynamicLibraries/WebPornSwap.dylib \
    -framework Foundation -lobjc "$B/WebPornSwap.o" -o "$B/WebPornSwap.dylib"
"$T/ldid" -S "$B/WebPornSwap.dylib"
D=/Library/MobileSubstrate/DynamicLibraries
scp -q "$B/WebPornSwap.dylib" "$HOST:$D/WebPornSwap.dylib.new"
scp -q "$WP/tweak/WebPornSwap.plist" "$HOST:$D/WebPornSwap.plist"
ssh "$HOST" "mv -f $D/WebPornSwap.dylib.new $D/WebPornSwap.dylib"
echo "installed WebPornSwap on $HOST"
