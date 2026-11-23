#!/bin/bash
# AVIF decoding for WebCore's AVIFImageDecoder: dav1d 1.4.3 (8-bit, NEON) +
# libavif 1.1.1 (decode only), one static archive. iOS 8's ImageIO has no AVIF.
#   build-avif.sh <arch> <min> <sdk-name>          e.g. armv7 8.0 iPhoneOS9.3
# Sources: src/dav1d (dav1d-1.4.3.tar.gz, sha256 88a023e5...6099), src/libavif
# (libavif-1.1.1.tar.gz, sha256 914662e1...b45b), both in src/dl; meson from
# build/mesonpkgs (pip install --target build/mesonpkgs meson).
# Output: prebuilt/<tag>/avif/{lib/libwpavif.a,include/avif}
set -euo pipefail
WP=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$1 MIN=$2 SDK=$3
TAG=$ARCH-ios${MIN%%.*}
P=$WP/prebuilt/$TAG/avif
B=$WP/build/avif-$TAG
SYSROOT=$WP/sdks/$SDK.sdk
rm -rf "$B" "$P"; mkdir -p "$B" "$P/lib" "$P/include"
CFLAGS="-target $ARCH-apple-ios$MIN -isysroot $SYSROOT -O2 -fvisibility=hidden"

cat > "$B/cross.txt" <<CROSS
[binaries]
c = 'clang'
ar = '/usr/lib/llvm-21/bin/llvm-ar'
strip = '/usr/lib/llvm-21/bin/llvm-strip'
[built-in options]
c_args = [$(printf "'%s', " $CFLAGS)]
c_link_args = ['-target', '$ARCH-apple-ios$MIN', '-isysroot', '$SYSROOT']
[host_machine]
system = 'darwin'
subsystem = 'ios'
kernel = 'xnu'
cpu_family = 'arm'
cpu = '$ARCH'
endian = 'little'
CROSS
PYTHONPATH=$WP/build/mesonpkgs python3 -m mesonbuild.mesonmain setup "$B/dav1d" "$WP/src/dav1d" --cross-file "$B/cross.txt" \
    --buildtype=release --default-library=static -Denable_tools=false -Denable_tests=false -Dbitdepths=8 \
    -Denable_asm=true -Dlogging=false >/dev/null
ninja -C "$B/dav1d" >/dev/null

# libavif: the decoder sources with the dav1d codec, no encoder / other codecs.
S=$WP/src/libavif
for src in alpha avif colr colrconvert diag exif io mem obu rawdata read reformat reformat_libyuv scale stream utils codec_dav1d; do
    [ -f "$S/src/$src.c" ] || continue
    clang $CFLAGS -I"$S/include" -I"$WP/src/dav1d/include" -I"$B/dav1d/include" -I"$B/dav1d/include/dav1d" \
        -DAVIF_CODEC_DAV1D=1 -c "$S/src/$src.c" -o "$B/avif_$src.o"
done
cp "$B/dav1d/src/libdav1d.a" "$P/lib/libwpavif.a"
/usr/lib/llvm-21/bin/llvm-ar rs "$P/lib/libwpavif.a" "$B"/avif_*.o
cp -r "$S/include/avif" "$P/include/"
ls -la "$P/lib/libwpavif.a"
