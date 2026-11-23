#!/bin/bash
# Configure the WebKit tree (branch webporn) for one iOS target.
#   configure-webkit.sh <arch> <min> <sdk-name> [extra cmake args...]
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3; shift 3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG
B=$WP/build/webkit-$TAG
# CMAKE_<LANG>_FLAGS on the command line replaces the toolchain's FLAGS_INIT, so repeat it.
BASE="-isystem $WP/toolchain/sdk-overlay/include -faligned-allocation"
CXXRT="$BASE -nostdinc++ -isystem $P/libcxx/include/c++/v1"
LINKRT="--ld-path=$HOME/theos/toolchain/linux/iphone/bin/ld -nostdlib++ -L$P/compat/lib -Wl,-hidden-lwpcxxcompat -lc++abi"

# The Web Port diff was not written for -Werror (e.g. #if 0'd code leaves unused functions).
cmake -G Ninja -S "$WP/src/webkit" -B "$B" \
    -DCMAKE_TOOLCHAIN_FILE="$WP/toolchain/ios.cmake" \
    -DWP_ARCH="$ARCH" -DWP_MIN="$MIN" -DWP_SDK="$WP/sdks/$SDK.sdk" \
    -DPORT=Mac -DWK_IOS_TARGET=ON \
    -DDEVELOPER_MODE_FATAL_WARNINGS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$BASE" -DCMAKE_OBJC_FLAGS="$BASE" \
    -DCMAKE_CXX_FLAGS="$CXXRT" -DCMAKE_OBJCXX_FLAGS="$CXXRT" \
    -DCMAKE_EXE_LINKER_FLAGS="$LINKRT" -DCMAKE_SHARED_LINKER_FLAGS="$LINKRT" \
    -DWK26_CXXFS_A="$P/libcxx/lib/libc++.a" \
    -DWEBPORN_COMPAT_A="$P/compat/lib/libwpcxxcompat.a" \
    -DWEBPORN_STUBS_DIR="$P/stubs" \
    -DWEBPORN_WEBP_DIR="$P/libwebp" \
    -DWEBPORN_AVIF_DIR="$P/avif" \
    -DWK26_ICU_DYLIB="$P/icu/dylib/libwpicu.dylib" \
    -DICU_INCLUDE_DIR="$P/icu/include" \
    -DWK26_WOFF2_A="$P/woff2/lib/libwpwoff2.a" -DWK26_WOFF2_INC="$P/woff2/include" \
    "$@"
