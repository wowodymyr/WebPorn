#!/bin/bash
# Sign and copy JavaScriptCore, WebCore and WebKitLegacy from a build dir to a device.
#   deploy-webkit.sh <build-tag> [ssh-host]     e.g. armv7-ios8 iphone
# Device layout: /var/webporn/lib/<Name>.framework/<Name>
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
TAG=$1 HOST=${2:-iphone}
B=$WP/build/webkit-$TAG
T=$HOME/theos/toolchain/linux/iphone/bin
ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT
for name in JavaScriptCore WebCore WebKitLegacy; do
    cp "$B/lib/$name.framework/$name" "$ST/$name"
    if "$T/otool" -l "$ST/$name" | grep -q "path $B/lib "; then
        "$T/install_name_tool" -rpath "$B/lib" /var/webporn/lib "$ST/$name"
    fi
    "$T/ldid" -S "$ST/$name"
done
for name in JavaScriptCore WebCore WebKitLegacy; do
    ssh "$HOST" "mkdir -p /var/webporn/lib/$name.framework"
    scp -q "$ST/$name" "$HOST:/var/webporn/lib/$name.framework/$name.new"
    ssh "$HOST" "mv /var/webporn/lib/$name.framework/$name.new /var/webporn/lib/$name.framework/$name"
done
# Resources looked up through the framework bundle: the media controls' icons
# (Apple's build flattens images/iOS into modern-media-controls/images).
MMC=$WP/src/webkit/Source/WebCore/Modules/modern-media-controls/images/iOS
tar -C "$MMC" -cf - . | ssh "$HOST" "rm -rf /var/webporn/lib/WebCore.framework/modern-media-controls; mkdir -p /var/webporn/lib/WebCore.framework/modern-media-controls/images && tar -C /var/webporn/lib/WebCore.framework/modern-media-controls/images -xf -"
scp -q "$B/lib/WebCore.framework/Info.plist" "$HOST:/var/webporn/lib/WebCore.framework/Info.plist"
echo "deployed $TAG frameworks to $HOST"
