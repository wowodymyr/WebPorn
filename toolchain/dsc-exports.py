#!/usr/bin/env python3
"""Dump the exported symbols of every image in a (pre-iOS 13) dyld shared cache.

  dsc-exports.py <dyld_shared_cache_xxx> <out.tsv>

Writes "install_name<TAB>symbol" lines, plus "install_name<TAB>@reexport<TAB>path"
for LC_REEXPORT_DYLIB, so check-undefs.py can resolve symbols the way dyld does.
"""
import mmap, struct, sys

LC_REQ_DYLD = 0x80000000
LC_REEXPORT_DYLIB = 0x1F | LC_REQ_DYLD
LC_DYLD_INFO = 0x22
LC_DYLD_INFO_ONLY = 0x22 | LC_REQ_DYLD
LC_DYLD_EXPORTS_TRIE = 0x33 | LC_REQ_DYLD
EXPORT_SYMBOL_FLAGS_REEXPORT = 0x08


def uleb(buf, pos):
    result = shift = 0
    while True:
        byte = buf[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        shift += 7
        if byte < 0x80:
            return result, pos


def walk_trie(buf, start, end):
    """Yield the names exported by the trie in buf[start:end]."""
    stack = [(start, b"")]
    while stack:
        node, prefix = stack.pop()
        if node >= end:
            continue
        info_len, pos = uleb(buf, node)
        if info_len:
            yield prefix.decode("utf-8", "replace")
        pos += info_len
        child_count = buf[pos]
        pos += 1
        for _ in range(child_count):
            nul = buf.find(b"\0", pos)
            edge = buf[pos:nul]
            child_off, pos = uleb(buf, nul + 1)
            stack.append((start + child_off, prefix + edge))


def main(cache_path, out_path):
    f = open(cache_path, "rb")
    buf = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    if not buf[:7] == b"dyld_v1":
        sys.exit("not a dyld shared cache")
    mapping_off, mapping_count, images_off, images_count = struct.unpack_from("<IIII", buf, 16)
    mappings = [struct.unpack_from("<QQQII", buf, mapping_off + 32 * i) for i in range(mapping_count)]

    def vm_to_file(addr):
        for address, size, file_off, _, _ in mappings:
            if address <= addr < address + size:
                return addr - address + file_off
        raise ValueError(hex(addr))

    out = open(out_path, "w")
    total = 0
    for i in range(images_count):
        address, _, _, path_off, _ = struct.unpack_from("<QQQII", buf, images_off + 32 * i)
        path = buf[path_off:buf.find(b"\0", path_off)].decode()
        hdr = vm_to_file(address)
        magic, _, _, _, ncmds, _, _ = struct.unpack_from("<IiiIIII", buf, hdr)
        lc = hdr + (32 if magic == 0xFEEDFACF else 28)
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", buf, lc)
            if cmd in (LC_DYLD_INFO, LC_DYLD_INFO_ONLY):
                export_off, export_size = struct.unpack_from("<II", buf, lc + 40)
                if export_size:
                    for name in walk_trie(buf, export_off, export_off + export_size):
                        out.write(f"{path}\t{name}\n")
                        total += 1
            elif cmd == LC_DYLD_EXPORTS_TRIE:
                export_off, export_size = struct.unpack_from("<II", buf, lc + 8)
                for name in walk_trie(buf, export_off, export_off + export_size):
                    out.write(f"{path}\t{name}\n")
                    total += 1
            elif cmd == LC_REEXPORT_DYLIB:
                name_off = struct.unpack_from("<I", buf, lc + 8)[0]
                target = buf[lc + name_off:buf.find(b"\0", lc + name_off)].decode()
                out.write(f"{path}\t@reexport\t{target}\n")
            lc += cmdsize
    print(f"{images_count} images, {total} exports -> {out_path}", file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:3])
