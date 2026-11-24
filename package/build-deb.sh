#!/bin/bash
# Package the engine, the swap tweaks and the Settings page as a .deb
# (build/net.webporn_<version>_iphoneos-arm.deb). The media engine (libvlc) and TLSFix
# are packages of their own.
#   package/build-deb.sh [build-tag]      default armv7-ios8
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:-armv7-ios8}
B=$WP/build/webkit-$TAG
T=$HOME/theos/toolchain/linux/iphone/bin
P=$WP/build/deb
rm -rf "$P"; mkdir -p "$P"
cp -r "$WP/package/DEBIAN" "$P/DEBIAN"

# Engine: /var/webporn/lib/<Name>.framework/<Name>, as device/deploy-webkit.sh lays it out.
L=$P/var/webporn/lib
for name in JavaScriptCore WebCore WebKitLegacy; do
    mkdir -p "$L/$name.framework"
    cp "$B/lib/$name.framework/$name" "$L/$name.framework/$name"
    if "$T/otool" -l "$L/$name.framework/$name" | grep -q "path $B/lib "; then
        "$T/install_name_tool" -rpath "$B/lib" /var/webporn/lib "$L/$name.framework/$name"
    fi
done
cp "$B/lib/WebCore.framework/Info.plist" "$L/WebCore.framework/Info.plist"
mkdir -p "$L/WebCore.framework/modern-media-controls/images"
cp -r "$WP/src/webkit/Source/WebCore/Modules/modern-media-controls/images/iOS/." "$L/WebCore.framework/modern-media-controls/images/"
cp "$WP/prebuilt/$TAG/icu/dylib/libwpicu.dylib" "$L/libwpicu.dylib"
for name in JavaScriptCore WebCore WebKitLegacy; do
    "$T/ldid" -S "$L/$name.framework/$name"
done
"$T/ldid" -S "$L/libwpicu.dylib"

# Tweaks and the Settings > WebPorn page.
D=$P/Library/MobileSubstrate/DynamicLibraries
mkdir -p "$D" "$P/Library/PreferenceLoader/Preferences"
for n in WebPornSwap WebPornSafari; do
    NAME=$n INSTALL=0 "$WP/tweak/build.sh"
    cp "$WP/build/tweak/$n.dylib" "$WP/tweak/$n.plist" "$D/"
done
cp "$WP/tweak/prefs/WebPorn.plist" "$P/Library/PreferenceLoader/Preferences/"

echo "Installed-Size: $(du -sk "$P" --exclude=DEBIAN | cut -f1)" >> "$P/DEBIAN/control"
PKG=$(sed -n 's/^Package: //p' "$P/DEBIAN/control")
VER=$(sed -n 's/^Version: //p' "$P/DEBIAN/control")
find "$P" -exec touch -h -d @0 {} +
OUT=$WP/build/${PKG}_${VER}_iphoneos-arm.deb
dpkg-deb --root-owner-group -Zgzip -b "$P" "$OUT" >/dev/null
echo "$OUT"
