#!/bin/bash
# WPBox: WPTest built and installed the way an App Store app is (an .ipa into a
# container, sandboxed, no entitlements: no JIT), to test the engine swap there.
# Its files (url.txt, probe.js, result.txt...) are in its Documents directory;
# `wpbox-dir` prints that path on the device.
#   tests/wptest/build-box.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/../.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
O=$WP/build/wpbox
B=$O/Payload/WPBox.app
SDK="-target armv7-apple-ios8.0 -isysroot $WP/sdks/iPhoneOS9.3.sdk"
rm -rf "$O"; mkdir -p "$B"
clang $SDK -O1 -fobjc-arc -fobjc-arc-exceptions -Wno-deprecated-declarations -DWP_SANDBOXED \
    -c "$WP/tests/wptest/main.m" -o "$O/main.o"
clang $SDK --ld-path="$T/ld" -framework UIKit -framework Foundation -framework CFNetwork -framework CoreGraphics \
    "$O/main.o" -o "$B/WPBox"
sed 's|<string>WPTest</string>|<string>WPBox</string>|g; s|net.webporn.wptest|net.webporn.wpbox|; s|<string>wptest</string>|<string>wpbox</string>|' \
    "$WP/tests/wptest/Info.plist" > "$B/Info.plist"
cp "$WP/tests/wptest/Default-568h@2x.png" "$B/"
"$T/ldid" -S "$B/WPBox"
(cd "$O" && rm -f WPBox.ipa && zip -qr WPBox.ipa Payload)
clang $SDK --ld-path="$T/ld" -framework Foundation -framework MobileCoreServices "$WP/tests/wptest/mi-install.m" -o "$O/mi-install"
"$T/ldid" -S "$O/mi-install"
scp -q "$O/WPBox.ipa" "$O/mi-install" "$WP/device/entitlements/mi-install.xml" "$HOST:/var/webporn/"
# installd only talks to holders of allowedSPI; entitlements must be signed on the device.
ssh "$HOST" 'chmod +x /var/webporn/mi-install && ldid -S/var/webporn/mi-install.xml /var/webporn/mi-install && /var/webporn/mi-install /var/webporn/WPBox.ipa net.webporn.wpbox'
echo "installed WPBox on $HOST"
