#!/bin/bash
# Build TLSFix (src/tlsfix) for armv7 iOS 8 against our OpenSSL 1.1.1w and install
# it with a filter limited to the WebPorn test apps (tweak/tlsfix.plist), unlike
# the upstream package, which injects into every CFNetwork process.
#   tweak/build-tlsfix.sh [ssh-host]
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
HOST=${1:-iphone}
T=$HOME/theos/toolchain/linux/iphone/bin
OSSL=$WP/prebuilt/armv7-ios8/openssl
B=$WP/build/tlsfix
mkdir -p "$B"
FLAGS=(-target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" -O2 -Wno-deprecated-declarations -I"$OSSL/include")
for src in tlsfix_engine tlsfix_hooks; do
    clang "${FLAGS[@]}" -c "$WP/src/tlsfix/src/$src.c" -o "$B/$src.o"
done
clang -target armv7-apple-ios8.0 -isysroot "$WP/sdks/iPhoneOS9.3.sdk" --ld-path="$T/ld" -dynamiclib \
    -install_name /Library/MobileSubstrate/DynamicLibraries/tlsfix.dylib \
    "$B/tlsfix_engine.o" "$B/tlsfix_hooks.o" "$OSSL/lib/libssl.a" "$OSSL/lib/libcrypto.a" \
    -F"$HOME/theos/vendor/lib" -framework CydiaSubstrate -framework Security -framework CoreFoundation \
    -o "$B/tlsfix.dylib"
"$T/ldid" -S "$B/tlsfix.dylib"
D=/Library/MobileSubstrate/DynamicLibraries
scp -q "$B/tlsfix.dylib" "$HOST:$D/tlsfix.dylib.new"
scp -q "$WP/tweak/tlsfix.plist" "$HOST:$D/tlsfix.plist"
ssh "$HOST" "mv -f $D/tlsfix.dylib.new $D/tlsfix.dylib"
echo "installed TLSFix on $HOST"
