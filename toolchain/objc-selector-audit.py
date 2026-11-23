#!/usr/bin/env python3
"""List selectors a Mach-O sends that no class or category in the target OS implements.

  objc-selector-audit.py <dyld_shared_cache_xxx | selectors.txt> <macho> [<macho>...]

Selectors come from each Mach-O's __objc_selrefs; implementations from the
instance and class method lists of every class and category in a (pre-iOS 13,
32- or 64-bit) shared cache plus the given Mach-Os themselves. Instead of a
cache, a text file with one implemented selector per line (tests/objc-methods.m
run on the device) can be given. A selector nobody implements is an
unrecognized-selector crash if it is ever sent without a respondsToSelector:
check, which is the case check-undefs.py cannot see. Receivers are not known
statically, so a selector some unrelated class happens to implement is not
reported.
"""
import mmap, re, struct, sys

LC_SEGMENT, LC_SEGMENT_64 = 0x1, 0x19
SELECTOR = re.compile(rb"[A-Za-z_][A-Za-z0-9_:]*\0")


class Image:
    """A Mach-O inside a shared cache or a standalone file, addressed by vmaddr.

    A cache copied out of a running device has some pointers rebased by the ASLR
    slide (the kernel slides a page when it is first touched) and others not,
    even within one structure, so every pointer is followed under both readings
    and the one whose target looks right is used.
    """

    def __init__(self, buf, header_off, vm_to_file, slide=0):
        self.buf, self.vm_to_file, self.slide = buf, vm_to_file, slide
        magic, _, _, _, ncmds, _, _ = struct.unpack_from("<IiiIIII", buf, header_off)
        self.is64 = magic == 0xFEEDFACF
        self.ptr = 8 if self.is64 else 4
        self.data_mask = ~7 if self.is64 else ~3  # class_t.bits flag bits
        self.sections = {}
        lc = header_off + (32 if self.is64 else 28)
        for _ in range(ncmds):
            cmd, cmdsize = struct.unpack_from("<II", buf, lc)
            if cmd in (LC_SEGMENT, LC_SEGMENT_64):
                nsects = struct.unpack_from("<I", buf, lc + (64 if self.is64 else 48))[0]
                sect = lc + (72 if self.is64 else 56)
                for _ in range(nsects):
                    name = buf[sect:sect + 16].rstrip(b"\0").decode()
                    if self.is64:
                        addr, size = struct.unpack_from("<QQ", buf, sect + 32)
                    else:
                        addr, size = struct.unpack_from("<II", buf, sect + 32)
                    self.sections.setdefault(name, []).append((addr, size))
                    sect += 80 if self.is64 else 68
            lc += cmdsize

    def raw(self, addr):
        value = struct.unpack_from("<Q" if self.is64 else "<I", self.buf, self.vm_to_file(addr))[0]
        return value & 0x0000000FFFFFFFFF if self.is64 else value  # strip pointer tags

    def follow(self, addr, valid):
        """The target of the pointer at addr under whichever reading passes valid()."""
        value = self.raw(addr)
        if not value:
            return 0
        for candidate in ((value, value - self.slide) if self.slide else (value,)):
            try:
                if valid(candidate):
                    return candidate
            except (ValueError, struct.error, IndexError):
                pass
        return 0

    def selector_at(self, addr):
        off = self.vm_to_file(addr)
        if off and self.buf[off - 1] != 0:
            return None
        m = SELECTOR.match(self.buf, off, off + 1024)
        return m.group()[:-1].decode() if m else None

    def is_method_list(self, addr):
        entsize_flags, count = struct.unpack_from("<II", self.buf, self.vm_to_file(addr))
        if (entsize_flags & 0xFFFC) != 3 * self.ptr or not 0 < count < 20000:
            return False
        return self.follow(addr + 8, self.selector_at) != 0

    def ro_name_offset(self):
        # class_ro_t: flags, instanceStart, instanceSize, [reserved], ivarLayout, name, baseMethods
        return 12 + (4 if self.is64 else 0) + self.ptr

    def is_class_ro(self, addr):
        return self.follow(addr + self.ro_name_offset(), self.selector_at) != 0

    def is_class(self, addr):
        return self.follow(addr + 4 * self.ptr, lambda a: self.is_class_ro(a & self.data_mask)) != 0

    def method_names(self, list_addr):
        if not list_addr:
            return
        count = struct.unpack_from("<I", self.buf, self.vm_to_file(list_addr) + 4)[0]
        for i in range(count):
            sel = self.follow(list_addr + 8 + i * 3 * self.ptr, self.selector_at)
            if sel:
                yield self.selector_at(sel)

    def class_methods(self, cls):
        if not cls:
            return
        ro = self.follow(cls + 4 * self.ptr, lambda a: self.is_class_ro(a & self.data_mask)) & self.data_mask
        if ro:
            yield from self.method_names(self.follow(ro + self.ro_name_offset() + self.ptr, self.is_method_list))

    def implemented(self):
        names = set()
        for addr, size in self.sections.get("__objc_classlist", []):
            for slot in range(addr, addr + size, self.ptr):
                try:
                    cls = self.follow(slot, self.is_class)
                    names.update(self.class_methods(cls))
                    names.update(self.class_methods(self.follow(cls, self.is_class)))  # metaclass
                except (ValueError, struct.error):
                    pass
        for addr, size in self.sections.get("__objc_catlist", []):
            for slot in range(addr, addr + size, self.ptr):
                try:
                    # category_t: name, cls, instanceMethods, classMethods
                    cat = self.follow(slot, lambda a: self.follow(a, self.selector_at) != 0)
                    for field in (2, 3):
                        names.update(self.method_names(self.follow(cat + field * self.ptr, self.is_method_list)))
                except (ValueError, struct.error):
                    pass
        return names

    def selrefs(self):
        result = set()
        for addr, size in self.sections.get("__objc_selrefs", []):
            for slot in range(addr, addr + size, self.ptr):
                sel = self.follow(slot, self.selector_at)
                if sel:
                    result.add(self.selector_at(sel))
        return result


def cache_images(path):
    f = open(path, "rb")
    buf = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    mapping_off, mapping_count, images_off, images_count = struct.unpack_from("<IIII", buf, 16)
    mappings = [struct.unpack_from("<QQQII", buf, mapping_off + 32 * i) for i in range(mapping_count)]

    def vm_to_file(addr):
        for address, size, file_off, _, _ in mappings:
            if address <= addr < address + size:
                return addr - address + file_off
        raise ValueError(hex(addr))

    addresses = [struct.unpack_from("<Q", buf, images_off + 32 * i)[0] for i in range(images_count)]
    images = [Image(buf, vm_to_file(address), vm_to_file) for address in addresses]

    # Find the slide from class lists that must point into their own __objc_data.
    votes = {}
    for image in images:
        data = image.sections.get("__objc_data")
        if not data or "__objc_classlist" not in image.sections:
            continue
        start, size = data[0]
        first = image.raw(image.sections["__objc_classlist"][0][0])
        if not start <= first < start + size:
            candidate = (first - start) & ~0xFFF
            guess = next((g for g in (candidate, candidate + 0x1000) if start <= first - g < start + size), None)
            if guess:
                votes[guess] = votes.get(guess, 0) + 1
    slide = max(votes, key=votes.get) if votes else 0
    if slide:
        print(f"# some cache pointers are slid by {slide:#x}", file=sys.stderr)
    for image in images:
        image.slide = slide
        yield image


def file_image(path):
    f = open(path, "rb")
    buf = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
    magic, _, _, _, ncmds, _, _ = struct.unpack_from("<IiiIIII", buf, 0)
    segments = []
    lc = 32 if magic == 0xFEEDFACF else 28
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, lc)
        if cmd == LC_SEGMENT_64:
            segments.append(struct.unpack_from("<QQQ", buf, lc + 24))
        elif cmd == LC_SEGMENT:
            segments.append(struct.unpack_from("<III", buf, lc + 24))
        lc += cmdsize

    def vm_to_file(addr):
        for vmaddr, vmsize, fileoff in segments:
            if vmaddr <= addr < vmaddr + vmsize:
                return addr - vmaddr + fileoff
        raise ValueError(hex(addr))

    return Image(buf, 0, vm_to_file)


def main(source, machos):
    if source.endswith(".txt"):
        implemented = {line.strip() for line in open(source) if line.strip()}
    else:
        implemented = set()
        for image in cache_images(source):
            implemented |= image.implemented()
    print(f"# {len(implemented)} selectors implemented in {source}", file=sys.stderr)
    images = [file_image(m) for m in machos]
    for image in images:
        implemented |= image.implemented()
    for path, image in zip(machos, images):
        missing = sorted(image.selrefs() - implemented)
        print(f"# {path}: {len(missing)} selectors not implemented anywhere", file=sys.stderr)
        for sel in missing:
            print(f"{path.rsplit('/', 1)[-1]}\t{sel}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
