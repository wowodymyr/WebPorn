#!/usr/bin/env python3
"""List undefined symbols of a Mach-O that the target OS does not export.

  check-undefs.py <sdk-dir | exports.tsv> <macho>

With an SDK, the exports come from its .tbd stubs. With exports.tsv (from
dsc-exports.py on a device's shared cache) they are exactly what that OS
version ships. Anything listed will fail to bind on device unless the stubs
library provides it.
"""
import pathlib, re, subprocess, sys

sdk, macho = pathlib.Path(sys.argv[1]), sys.argv[2]
nm = pathlib.Path.home() / "theos/toolchain/linux/iphone/bin/nm"

exported = set()
if sdk.is_file():
    for line in sdk.open():
        fields = line.rstrip("\n").split("\t")
        if len(fields) == 2:
            exported.add(fields[1])
for tbd in (sdk.rglob("*.tbd") if sdk.is_dir() else []):
    text = tbd.read_text(errors="replace")
    for block in re.findall(r"(?:symbols|objc-classes|objc-ivars|weak-def-symbols|thread-local-symbols|re-exports)\s*:\s*\[([^\]]*)\]", text):
        for sym in re.split(r"[,\s]+", block):
            sym = sym.strip().strip("'\"")
            if sym:
                exported.add(sym)
    for cls in re.findall(r"objc-classes\s*:\s*\[([^\]]*)\]", text):
        for c in re.split(r"[,\s]+", cls):
            c = c.strip().strip("'\"").lstrip("_")
            if c:
                exported.add("_OBJC_CLASS_$_" + c)
                exported.add("_OBJC_METACLASS_$_" + c)

undefs = subprocess.run([nm, "-u", macho], capture_output=True, text=True).stdout.split()
missing = [s for s in undefs if s not in exported and s != "dyld_stub_binder"]
print("\n".join(missing))
print(f"# {len(missing)} of {len(undefs)} undefined symbols not exported by {sdk.name}", file=sys.stderr)
