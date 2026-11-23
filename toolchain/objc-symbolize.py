#!/usr/bin/env python3
"""Symbolize addresses inside an app binary by its ObjC method list (nearest IMP below).

  objc-symbolize.py <macho> <load-address> <addr>...
Addresses are runtime addresses from a crash report; <load-address> is the
image base the report shows (e.g. 0x1b000). Good enough for stripped apps."""
import bisect, re, subprocess, sys

macho, base = sys.argv[1], int(sys.argv[2], 16)
out = subprocess.run(["/usr/lib/llvm-21/bin/llvm-objdump", "--macho", "--objc-meta-data", macho],
                     capture_output=True, text=True).stdout
hdr = subprocess.run(["/usr/lib/llvm-21/bin/llvm-objdump", "--macho", "--private-headers", macho],
                     capture_output=True, text=True).stdout
vmaddr = int(re.search(r"segname __TEXT\n\s+vmaddr 0x([0-9a-f]+)", hdr).group(1), 16)
syms, cls, meta, last = [], "?", False, "?"
for line in out.splitlines():
    if line.startswith("Meta Class"):
        meta = True
    elif re.match(r"^[0-9a-f]{8} 0x", line):
        meta = False
    m = re.match(r"^ {21}name 0x[0-9a-f]+ (\S+)$", line)
    if m:
        cls = m.group(1)
    m = re.match(r"^\t\t\s+name 0x[0-9a-f]+ (\S+)$", line)
    if m:
        last = m.group(1)
    m = re.match(r"^\t\t\s+imp 0x([0-9a-f]+)$", line)
    if m:
        syms.append((int(m.group(1), 16) & ~1, ("+" if meta else "-") + "[" + cls + " " + last + "]"))
syms.sort()
keys = [s[0] for s in syms]
for a in sys.argv[3:]:
    addr = int(a, 16) - base + vmaddr
    k = bisect.bisect_right(keys, addr) - 1
    print(f"{a}: {syms[k][1]} + {addr - syms[k][0]:#x}" if k >= 0 else f"{a}: ?")
