#!/usr/bin/env python3
"""List undefined symbols of a Mach-O that no .tbd in the SDK exports.

  check-undefs.py <sdk> <macho>

The SDK's .tbd stubs describe what the OS exports, so anything left over will
fail to bind on device unless the stubs library provides it.
"""
import pathlib, re, subprocess, sys

sdk, macho = pathlib.Path(sys.argv[1]), sys.argv[2]
nm = pathlib.Path.home() / "theos/toolchain/linux/iphone/bin/nm"

exported = set()
for tbd in sdk.rglob("*.tbd"):
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
