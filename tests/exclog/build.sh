#!/bin/bash
# Build ExcLog.dylib (armv7, iOS 8) and install it as a Substrate tweak.
#   tests/exclog/build.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/../.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
B=$WP/build/exclog
mkdir -p "$B"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O1 -Wall -c "$WP/tests/exclog/ExcLog.m" -o "$B/ExcLog.o"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" -dynamiclib \
    -install_name /Library/MobileSubstrate/DynamicLibraries/ExcLog.dylib \
    -framework Foundation "$B/ExcLog.o" -o "$B/ExcLog.dylib" 2>&1 | grep -v "built for iOS Simulator" || true
"$T/ldid" -S "$B/ExcLog.dylib"
D=/Library/MobileSubstrate/DynamicLibraries
scp -q "$B/ExcLog.dylib" "$HOST:$D/ExcLog.dylib.new"
scp -q "$WP/tests/exclog/ExcLog.plist" "$HOST:$D/ExcLog.plist"
ssh "$HOST" "mv -f $D/ExcLog.dylib.new $D/ExcLog.dylib"
echo "installed ExcLog on $HOST"
