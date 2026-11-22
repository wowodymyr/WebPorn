#!/bin/bash
# Configure the WebKit tree (branch webporn) for one iOS target.
#   configure-webkit.sh <arch> <min> <sdk-name> [extra cmake args...]
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3; shift 3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG
B=$WP/build/webkit-$TAG
CXXRT="-nostdinc++ -isystem $P/libcxx/include/c++/v1"
LINKRT="--ld-path=$HOME/theos/toolchain/linux/iphone/bin/ld -nostdlib++ -L$P/compat/lib -Wl,-hidden-lwpcxxcompat -lc++abi"

cmake -G Ninja -S "$WP/src/webkit" -B "$B" \
    -DCMAKE_TOOLCHAIN_FILE="$WP/toolchain/ios.cmake" \
    -DWP_ARCH="$ARCH" -DWP_MIN="$MIN" -DWP_SDK="$WP/sdks/$SDK.sdk" \
    -DPORT=Mac -DWK_IOS_TARGET=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="$CXXRT" -DCMAKE_OBJCXX_FLAGS="$CXXRT" \
    -DCMAKE_EXE_LINKER_FLAGS="$LINKRT" -DCMAKE_SHARED_LINKER_FLAGS="$LINKRT" \
    -DWK26_CXXFS_A="$P/libcxx/lib/libc++.a" \
    -DWK26_ICU_DYLIB="$P/icu/dylib/libwpicu.dylib" \
    -DICU_INCLUDE_DIR="$P/icu/include" \
    -DWK26_WOFF2_A="$P/woff2/lib/libwpwoff2.a" -DWK26_WOFF2_INC="$P/woff2/include" \
    "$@"
