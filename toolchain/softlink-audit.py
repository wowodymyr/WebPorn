#!/usr/bin/env python3
"""List hard soft-links (RELEASE_ASSERT on failure) that the target OS cannot satisfy.

  softlink-audit.py <exports.tsv> <webkit-src> <macho> [<macho>...]

WebKit's SOFT_LINK* macros dlsym() a framework symbol (or objc_getClass a class)
the first time it is used; the non-OPTIONAL / non-MAY_FAIL variants crash when
it is missing. The names actually linked into a binary are collected in its
__TEXT,__dlsym_cstr and __TEXT,__getClass_cstr sections; the macro kind comes
from the sources. A name listed here crashes the process when that code runs.
"""
import pathlib, re, struct, sys

exports_path, src, machos = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3:]

exported = set()
for line in open(exports_path):
    fields = line.rstrip("\n").split("\t")
    if len(fields) == 2:
        exported.add(fields[1])


def section_strings(macho, section):
    """NUL-separated strings of __TEXT,<section> (32- or 64-bit, thin Mach-O)."""
    data = pathlib.Path(macho).read_bytes()
    magic, = struct.unpack_from("<I", data, 0)
    is64 = magic == 0xFEEDFACF
    ncmds, = struct.unpack_from("<I", data, 16)
    lc = 32 if is64 else 28
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, lc)
        if cmd in (0x1, 0x19):
            nsects, = struct.unpack_from("<I", data, lc + (64 if is64 else 48))
            sect = lc + (72 if is64 else 56)
            for _ in range(nsects):
                name = data[sect:sect + 16].rstrip(b"\0").decode()
                if name == section:
                    size, = struct.unpack_from("<Q" if is64 else "<I", data, sect + (40 if is64 else 36))
                    offset, = struct.unpack_from("<I", data, sect + (48 if is64 else 40))
                    return {x.decode() for x in data[offset:offset + size].split(b"\0") if x}
                sect += 80 if is64 else 68
        lc += cmdsize
    return set()


linked_symbols, linked_classes = set(), set()
for macho in machos:
    linked_symbols |= section_strings(macho, "__dlsym_cstr")
    linked_classes |= section_strings(macho, "__getClass_cstr")


def macro_args(text, start):
    """Top-level comma-separated arguments of the macro call whose '(' is at start."""
    depth, args, current = 0, [], []
    for ch in text[start:]:
        if ch == "(":
            depth += 1
            if depth == 1:
                continue
        elif ch == ")":
            depth -= 1
            if depth == 0:
                args.append("".join(current).strip())
                return args
        if ch == "," and depth == 1:
            args.append("".join(current).strip())
            current = []
        else:
            current.append(ch)
    return args


hard = {}  # name -> (kind, framework, file:line)
macro = re.compile(r"\b(SOFT_LINK[A-Z_]*)\s*\(")
for path in list(src.glob("Source/WebCore/**/*")) + list(src.glob("Source/WebKitLegacy/**/*")) + list(src.glob("Source/WTF/**/*")):
    if path.suffix not in (".mm", ".m", ".cpp", ".h") or "/testing/" in str(path):
        continue
    text = path.read_text(errors="replace")
    if "SOFT_LINK" not in text:
        continue
    for m in macro.finditer(text):
        name = m.group(1)
        if any(word in name for word in ("OPTIONAL", "MAY_FAIL", "FRAMEWORK", "LIBRARY", "IS_AVAILABLE", "FOR_HEADER", "DECLARE")):
            continue
        if text[:m.start()].rstrip().endswith("#define"):
            continue
        args = macro_args(text, m.end() - 1)
        index = 2 if "FOR_SOURCE" in name else 1
        if len(args) <= index:
            continue
        kind = "class" if "CLASS" in name else "symbol"
        line = text.count("\n", 0, m.start()) + 1
        hard.setdefault(args[index], (kind, args[index - 1], f"{path.relative_to(src)}:{line}"))

missing = []
for name, (kind, framework, where) in sorted(hard.items()):
    if kind == "symbol" and name in linked_symbols and "_" + name not in exported:
        missing.append((name, framework, where))
    elif kind == "class" and name in linked_classes and f"_OBJC_CLASS_$_{name}" not in exported:
        missing.append((name, framework, where))
for name, framework, where in missing:
    print(f"{name}\t{framework}\t{where}")
print(f"# {len(missing)} hard soft-links missing; {len(hard)} hard macros, "
      f"{len(linked_symbols)} dlsym / {len(linked_classes)} getClass names linked", file=sys.stderr)
