#!/usr/bin/env python3
"""Dump ObjC classes of a Mach-O as JSON {class: {super, instance: [...], class_methods: [...]}}.

  objc-classes.py <macho> > classes.json
Superclasses outside the image show as the bound symbol name when objdump knows it."""
import json, re, subprocess, sys

out = subprocess.run(["/usr/lib/llvm-21/bin/llvm-objdump", "--macho", "--objc-meta-data", sys.argv[1]],
                     capture_output=True, text=True).stdout
classes, addr2name, cur, meta, pending = {}, {}, None, False, []
for line in out.splitlines():
    m = re.match(r"^([0-9a-f]{8}) 0x([0-9a-f]+)", line)
    if m:
        meta, cur = False, None
        pending.append([int(m.group(2), 16), None, None])
        continue
    if line.startswith("Meta Class"):
        meta = True
        continue
    m = re.match(r"^\s+superclass 0x([0-9a-f]+)(?: (\S+))?", line)
    if m and not meta and pending:
        pending[-1][2] = m.group(2) or int(m.group(1), 16)
    m = re.match(r"^ {21}name 0x[0-9a-f]+ (\S+)$", line)
    if m:
        cur = m.group(1)
        if not meta:
            pending[-1][1] = cur
            addr2name[pending[-1][0]] = cur
        classes.setdefault(cur, {"super": None, "instance": [], "class_methods": []})
    m = re.match(r"^\t\t\s+name 0x[0-9a-f]+ (\S+)$", line)
    if m and cur:
        classes[cur]["class_methods" if meta else "instance"].append(m.group(1))
for addr, name, sup in pending:
    if name:
        classes[name]["super"] = addr2name.get(sup, sup) if isinstance(sup, int) else (sup or "").replace("_OBJC_CLASS_$_", "")
json.dump(classes, sys.stdout, indent=1)
