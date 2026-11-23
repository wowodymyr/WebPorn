#!/bin/bash
# Static OpenSSL 1.1.1w (libssl.a + libcrypto.a) for TLSFix.
#   build-openssl.sh <arch> <min> <sdk-name>     e.g. armv7 8.0 iPhoneOS9.3
# Output: prebuilt/<arch>-ios<major>/openssl/{lib,include}
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
OUT=$WP/prebuilt/$TAG/openssl
B=$WP/build/openssl-$TAG
rm -rf "$B" "$OUT"; mkdir -p "$B" "$OUT"
tar -C "$B" --strip-components=1 -xzf "$WP/src/dl/openssl-1.1.1w.tar.gz"
cd "$B"
# iphoneos-cross adds -isysroot $(CROSS_TOP)/SDKs/$(CROSS_SDK); give it that layout.
mkdir -p "$B/xsdk/SDKs" && ln -s "$WP/sdks/$SDK.sdk" "$B/xsdk/SDKs/$SDK.sdk"
export CROSS_TOP=$B/xsdk CROSS_SDK=$SDK.sdk
export CC="clang -target $ARCH-apple-ios$MIN"
export AR=/usr/lib/llvm-21/bin/llvm-ar RANLIB=/usr/lib/llvm-21/bin/llvm-ranlib
# no-asm: perlasm's armv4 output targets Apple's old assembler syntax; the C
# paths are fine (armv7 has no AES/SHA instructions to gain from anyway).
./Configure iphoneos-cross no-shared no-tests no-asm no-engine no-dso no-async no-comp \
    no-ssl3 no-weak-ssl-ciphers --prefix="$OUT" --openssldir=/var/webporn/ssl \
    -fvisibility=hidden >/dev/null
make -j"$(nproc)" build_libs >/dev/null
make install_dev >/dev/null
echo "$OUT"
