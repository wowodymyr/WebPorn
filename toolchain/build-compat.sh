#!/bin/bash
# libwpcxxcompat.a: runtime pieces older iOS lacks (sized/aligned new/delete,
# clock_gettime). Link with -Wl,-hidden-lwpcxxcompat.
#   build-compat.sh <arch> <min> <sdk-name>
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG
B=$WP/build/compat-$TAG
rm -rf "$B"; mkdir -p "$B" "$P/compat/lib"
FLAGS=(-target "$ARCH-apple-ios$MIN" -isysroot "$WP/sdks/$SDK.sdk" -O2
       -isystem "$WP/toolchain/sdk-overlay/include" -fvisibility=hidden)
clang++ "${FLAGS[@]}" -std=c++23 -nostdinc++ -isystem "$P/libcxx/include/c++/v1" -fno-exceptions \
    -c "$WP/toolchain/compat/cxx_new_compat.cpp" -o "$B/cxx_new_compat.o"
clang "${FLAGS[@]}" -c "$WP/toolchain/compat/time_compat.c" -o "$B/time_compat.o"
rm -f "$P/compat/lib/libwpcxxcompat.a"
/usr/lib/llvm-21/bin/llvm-ar rcs "$P/compat/lib/libwpcxxcompat.a" "$B"/*.o
echo "$P/compat/lib/libwpcxxcompat.a"
