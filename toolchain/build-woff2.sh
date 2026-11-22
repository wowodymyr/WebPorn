#!/bin/bash
# Decode-only WOFF2 (woff2 1.0.2 + brotli 1.1.0 decoder) as one static archive
# for WebKit's WOFF2::dec target (passed in as WK26_WOFF2_A / WK26_WOFF2_INC).
#   build-woff2.sh <arch> <min> <sdk-name>
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG
B=$WP/build/woff2-$TAG
rm -rf "$B"; mkdir -p "$B" "$P/woff2/lib" "$P/woff2/include"
FLAGS=(-target "$ARCH-apple-ios$MIN" -isysroot "$WP/sdks/$SDK.sdk" -isystem "$WP/toolchain/sdk-overlay/include"
       -O2 -fvisibility=hidden -I"$WP/src/brotli/c/include")
for src in "$WP"/src/brotli/c/common/*.c "$WP"/src/brotli/c/dec/*.c; do
    clang "${FLAGS[@]}" -c "$src" -o "$B/brotli_$(basename "${src%.c}").o"
done
for name in woff2_dec woff2_out table_tags variable_length woff2_common; do
    clang++ "${FLAGS[@]}" -std=c++23 -nostdinc++ -isystem "$P/libcxx/include/c++/v1" -faligned-allocation -fno-exceptions \
        -fvisibility-inlines-hidden -I"$WP/src/woff2/include" -c "$WP/src/woff2/src/$name.cc" -o "$B/woff2_$name.o"
done
rm -f "$P/woff2/lib/libwpwoff2.a"
/usr/lib/llvm-21/bin/llvm-ar rcs "$P/woff2/lib/libwpwoff2.a" "$B"/*.o
cp -r "$WP/src/woff2/include/woff2" "$P/woff2/include/"
ls -la "$P/woff2/lib/libwpwoff2.a"
