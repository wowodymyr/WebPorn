#!/bin/bash
# Sign and copy jsc + JavaScriptCore.framework from a build dir to a device.
#   deploy-jsc.sh <build-tag> [ssh-host]     e.g. armv7-ios8 iphone
# Device layout: /var/webporn/bin/jsc, /var/webporn/lib/JavaScriptCore.framework/
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
TAG=$1 HOST=${2:-iphone}
B=$WP/build/webkit-$TAG
T=$HOME/theos/toolchain/linux/iphone/bin
ST=$(mktemp -d)
trap 'rm -rf "$ST"' EXIT
cp "$B/bin/jsc" "$B/lib/JavaScriptCore.framework/JavaScriptCore" "$ST/"
"$T/install_name_tool" -rpath "$B/lib" /var/webporn/lib "$ST/jsc"
"$T/ldid" -S "$ST/JavaScriptCore"
ssh "$HOST" 'mkdir -p /var/webporn/bin /var/webporn/lib/JavaScriptCore.framework'
scp -q "$ST/jsc" "$HOST:/var/webporn/bin/jsc"
scp -q "$ST/JavaScriptCore" "$HOST:/var/webporn/lib/JavaScriptCore.framework/JavaScriptCore"
# iOS 8 kills binaries whose entitlements were signed by the host (procursus) ldid;
# the device's own ldid works, so add the JIT entitlement there.
scp -q "$WP/device/entitlements/jsc.xml" "$HOST:/var/webporn/jsc-ent.xml"
ssh "$HOST" 'ldid -S/var/webporn/jsc-ent.xml /var/webporn/bin/jsc && rm -f /var/webporn/bin/jsc.t'
echo "deployed $TAG to $HOST"
