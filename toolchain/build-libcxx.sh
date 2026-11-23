#!/bin/bash
# Static, hermetic libc++ (ABI namespace std::__wp) for one iOS target.
#   build-libcxx.sh <arch> <min> <sdk-name>    e.g. arm64 10.0 iPhoneOS10.3
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
B=$WP/build/libcxx-$TAG
rm -rf "$B"
cmake -G Ninja -S "$WP/src/llvm-project/runtimes" -B "$B" \
    -DCMAKE_TOOLCHAIN_FILE="$WP/toolchain/ios.cmake" \
    -DWP_ARCH="$ARCH" -DWP_MIN="$MIN" -DWP_SDK="$WP/sdks/$SDK.sdk" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$WP/prebuilt/$TAG/libcxx" \
    -DLLVM_ENABLE_RUNTIMES=libcxx \
    -DLIBCXX_ENABLE_SHARED=OFF -DLIBCXX_ENABLE_STATIC=ON -DLIBCXX_HERMETIC_STATIC_LIBRARY=ON \
    -DLIBCXX_ABI_NAMESPACE=__wp -DLIBCXX_CXX_ABI=system-libcxxabi \
    -DLIBCXX_CXX_ABI_INCLUDE_PATHS="$WP/src/llvm-project/libcxxabi/include" \
    -DLIBCXX_ENABLE_VENDOR_AVAILABILITY_ANNOTATIONS=OFF -DLIBCXX_ENABLE_TIME_ZONE_DATABASE=OFF \
    -DLIBCXX_INCLUDE_TESTS=OFF -DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_TESTS=OFF \
    > "$B.configure.log"
ninja -C "$B" install
# system-libcxxabi does not install the ABI headers; WTF includes <cxxabi.h> (__cxa_demangle).
cp "$WP/src/llvm-project/libcxxabi/include/"{cxxabi.h,__cxxabi_config.h} "$WP/prebuilt/$TAG/libcxx/include/c++/v1/"
