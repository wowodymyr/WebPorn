#!/bin/bash
# Build WPTest.app for armv7 iOS 8 and install it on the device.
#   tests/wptest/build.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/../.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
B=$WP/build/wptest/WPTest.app
rm -rf "$B"; mkdir -p "$B"
# Compile and link separately: with -fobjc-arc at link time clang wants
# libarclite for this deployment target, which the open-source toolchain lacks.
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O1 -fobjc-arc -fobjc-arc-exceptions \
    -Wno-deprecated-declarations -c "$WP/tests/wptest/main.m" -o "$B/../main.o"
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" \
    -framework UIKit -framework Foundation -framework CFNetwork -framework CoreGraphics "$B/../main.o" -o "$B/WPTest"
cp "$WP/tests/wptest/Info.plist" "$B/"
"$T/ldid" -S "$B/WPTest"
ssh "$HOST" 'rm -rf /Applications/WPTest.app.new; mkdir -p /var/mobile/Media/webporn; chown mobile:mobile /var/mobile/Media/webporn'
scp -O -qr "$B" "$HOST:/Applications/WPTest.app.new"
# JIT needs dynamic-codesigning; iOS 8 kills binaries whose entitlements were
# signed by the host ldid, so sign them on the device (as deploy-jsc.sh does).
scp -q "$WP/device/entitlements/jsc.xml" "$HOST:/var/webporn/jsc-ent.xml"
ssh "$HOST" 'ldid -S/var/webporn/jsc-ent.xml /Applications/WPTest.app.new/WPTest && rm -rf /Applications/WPTest.app && mv /Applications/WPTest.app.new /Applications/WPTest.app && su mobile -c uicache'
echo "installed WPTest.app on $HOST"
