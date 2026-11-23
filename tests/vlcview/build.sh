#!/bin/bash
# Build VLCView.app (armv7, iOS 8) against prebuilt MobileVLCKit and install it.
#   tests/vlcview/build.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/../.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
VLC=$WP/prebuilt/armv7-ios8/vlc/MobileVLCKit.framework
B=$WP/build/vlcview/VLCView.app
rm -rf "$B"; mkdir -p "$B"
clang -target armv7-apple-ios8.4 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O1 -fobjc-arc -I"$VLC/Headers" \
    -c "$WP/tests/vlcview/main.m" -o "$B/../main.o"
clang -target armv7-apple-ios8.4 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" \
    -framework UIKit -framework Foundation "$VLC/MobileVLCKit" "$B/../main.o" -o "$B/VLCView" 2>&1 | grep -v "built for iOS Simulator" || true
cp "$WP/tests/vlcview/Info.plist" "$B/"
ssh "$HOST" 'rm -rf /Applications/VLCView.app.new'
scp -O -qr "$B" "$HOST:/Applications/VLCView.app.new"
ssh "$HOST" 'ldid -S /Applications/VLCView.app.new/VLCView && rm -rf /Applications/VLCView.app && mv /Applications/VLCView.app.new /Applications/VLCView.app && su mobile -c uicache'
echo "installed VLCView.app on $HOST"
