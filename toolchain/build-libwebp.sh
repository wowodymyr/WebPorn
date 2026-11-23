#!/bin/bash
# Decode-only libwebp 1.4.0 (decoder + demux, NEON dsp) as one static archive for
# WebCore's WEBPImageDecoder: iOS 8's ImageIO has no WebP.
#   build-libwebp.sh <arch> <min> <sdk-name>       e.g. armv7 8.0 iPhoneOS9.3
# Source: src/libwebp (libwebp-1.4.0.tar.gz, sha256 61f873ec...ab1e5, in src/dl).
# Output: prebuilt/<tag>/libwebp/{lib/libwpwebp.a,include/webp}
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG/libwebp
B=$WP/build/libwebp-$TAG
S=$WP/src/libwebp
rm -rf "$B" "$P"; mkdir -p "$B" "$P/lib" "$P/include/webp"
FLAGS=(-target "$ARCH-apple-ios$MIN" -isysroot "$WP/sdks/$SDK.sdk" -O2 -fvisibility=hidden -I"$S")
for src in "$S"/src/dec/*.c "$S"/src/demux/demux.c "$S"/src/utils/*.c "$S"/src/dsp/*.c; do
    case $(basename "$src") in
        # Encoder-only parts.
        bit_writer_utils.c|huffman_encode_utils.c|quant_levels_utils.c|enc*.c|cost*.c|ssim*.c|lossless_enc*.c) continue ;;
    esac
    dir=$(basename "$(dirname "$src")")
    clang "${FLAGS[@]}" -c "$src" -o "$B/${dir}_$(basename "${src%.c}").o"
done
/usr/lib/llvm-21/bin/llvm-ar rcs "$P/lib/libwpwebp.a" "$B"/*.o
cp "$S"/src/webp/decode.h "$S"/src/webp/demux.h "$S"/src/webp/types.h "$S"/src/webp/mux_types.h "$P/include/webp/"
ls -la "$P/lib/libwpwebp.a"
