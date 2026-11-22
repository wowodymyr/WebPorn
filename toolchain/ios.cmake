# Cross-compile for jailbroken iOS from Linux: system clang + Theos ld64.
#   -DWP_ARCH=arm64|armv7  -DWP_MIN=10.0|8.0  -DWP_SDK=/path/iPhoneOSx.y.sdk

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR ${WP_ARCH})
set(CMAKE_OSX_ARCHITECTURES ${WP_ARCH} CACHE STRING "")
set(CMAKE_OSX_SYSROOT ${WP_SDK} CACHE PATH "")
set(CMAKE_OSX_DEPLOYMENT_TARGET ${WP_MIN} CACHE STRING "")

# Toolchain files are re-read by try_compile; pass the WP_* settings through.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES WP_ARCH WP_MIN WP_SDK)

set(WP_THEOS_BIN $ENV{HOME}/theos/toolchain/linux/iphone/bin)
set(WP_TRIPLE ${WP_ARCH}-apple-ios${WP_MIN})

set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)
set(CMAKE_OBJC_COMPILER clang)
set(CMAKE_OBJCXX_COMPILER clang++)
foreach(lang C CXX OBJC OBJCXX ASM)
    set(CMAKE_${lang}_COMPILER_TARGET ${WP_TRIPLE})
    # Fixes for old-SDK headers that modern libc++/WebKit trip over.
    set(CMAKE_${lang}_FLAGS_INIT "-isystem ${CMAKE_CURRENT_LIST_DIR}/sdk-overlay/include")
endforeach()

set(CMAKE_AR /usr/lib/llvm-21/bin/llvm-ar CACHE FILEPATH "")
set(CMAKE_RANLIB /usr/lib/llvm-21/bin/llvm-ranlib CACHE FILEPATH "")
set(CMAKE_LIBTOOL ${WP_THEOS_BIN}/libtool CACHE FILEPATH "")
set(CMAKE_INSTALL_NAME_TOOL ${WP_THEOS_BIN}/install_name_tool CACHE FILEPATH "")
set(CMAKE_LIPO ${WP_THEOS_BIN}/lipo CACHE FILEPATH "")
set(CMAKE_NM ${WP_THEOS_BIN}/nm CACHE FILEPATH "")
set(CMAKE_OTOOL ${WP_THEOS_BIN}/otool CACHE FILEPATH "")
set(CMAKE_STRIP ${WP_THEOS_BIN}/strip CACHE FILEPATH "")

set(CMAKE_EXE_LINKER_FLAGS_INIT "--ld-path=${WP_THEOS_BIN}/ld")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "--ld-path=${WP_THEOS_BIN}/ld")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "--ld-path=${WP_THEOS_BIN}/ld")

set(CMAKE_FIND_ROOT_PATH ${WP_SDK})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
