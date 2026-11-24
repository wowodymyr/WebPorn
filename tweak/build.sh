#!/bin/bash
# Build a tweak (armv7, iOS 8) and install it as a Substrate tweak.
#   [NAME=WebPornSwap|WebPornSafari] [INSTALL=0] tweak/build.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
HOST=${1:-iphone}
N=${NAME:-WebPornSwap}
T=$HOME/theos/toolchain/linux/iphone/bin
B=$WP/build/tweak
mkdir -p "$B"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O1 -Wall -Wno-unused-function \
    -c "$WP/tweak/$N.m" -o "$B/$N.o"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" -dynamiclib \
    -install_name /Library/MobileSubstrate/DynamicLibraries/$N.dylib \
    -framework Foundation -framework UIKit -lobjc "$B/$N.o" -o "$B/$N.dylib" 2>&1 | grep -v "built for iOS Simulator" || true
"$T/ldid" -S "$B/$N.dylib"
[ "${INSTALL:-1}" = 1 ] || exit 0
D=/Library/MobileSubstrate/DynamicLibraries
scp -q "$B/$N.dylib" "$HOST:$D/$N.dylib.new"
scp -q "$WP/tweak/$N.plist" "$HOST:$D/$N.plist"
ssh "$HOST" "mv -f $D/$N.dylib.new $D/$N.dylib"
if [ "$N" = WebPornSwap ]; then
    # Settings > WebPorn (AppList switches).
    scp -q "$WP/tweak/prefs/WebPorn.plist" "$HOST:/Library/PreferenceLoader/Preferences/WebPorn.plist"
fi
echo "installed $N on $HOST"
