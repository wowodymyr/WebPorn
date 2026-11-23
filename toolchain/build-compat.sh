#!/bin/bash
# libwpcxxcompat.a: runtime pieces older iOS lacks (sized/aligned new/delete,
# clock_gettime, newer __cxa_* entry points, iOS 10 libSystem calls). Link with
# -Wl,-hidden-lwpcxxcompat (or -Wl,-load_hidden,<path>).
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
clang++ "${FLAGS[@]}" -std=c++23 -nostdinc++ -isystem "$P/libcxx/include/c++/v1" -fno-exceptions \
    -c "$WP/toolchain/compat/cxx_abi_compat.cpp" -o "$B/cxx_abi_compat.o"
clang "${FLAGS[@]}" -c "$WP/toolchain/compat/time_compat.c" -o "$B/time_compat.o"
clang "${FLAGS[@]}" -c "$WP/toolchain/compat/system_compat.c" -o "$B/system_compat.o"
clang "${FLAGS[@]}" -c "$WP/toolchain/compat/webcore_compat.c" -o "$B/webcore_compat.o"
clang "${FLAGS[@]}" -c "$WP/toolchain/compat/webcore_ios8_compat.c" -o "$B/webcore_ios8_compat.o"
clang "${FLAGS[@]}" -fobjc-arc -c "$WP/toolchain/compat/webcore_ios8_compat.m" -o "$B/webcore_ios8_compat_objc.o"
clang "${FLAGS[@]}" -fobjc-arc -c "$WP/toolchain/compat/uttype_compat.m" -o "$B/uttype_compat.o"
rm -f "$P/compat/lib/libwpcxxcompat.a"
/usr/lib/llvm-21/bin/llvm-ar rcs "$P/compat/lib/libwpcxxcompat.a" "$B"/*.o
echo "$P/compat/lib/libwpcxxcompat.a"
