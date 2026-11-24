#!/usr/bin/env python3
"""Find where the selectors objc-selector-audit.py reports are used in the sources.

  selector-triage.py <audit.tsv> <source-root> [--sends-only] [--shims compat.m]

For each selector: 'guard' uses (respondsToSelector:/instancesRespondToSelector:
with it), '@selector' references (delegate dispatch that checks first, method
lists, performSelector...), and message 'send's, which need a look: an
unguarded send to a class that exists on the device but lacks the method is
an unrecognized-selector crash.
"""
import os, re, sys

audit, root = sys.argv[1], sys.argv[2]
sends_only = "--sends-only" in sys.argv
rows = [l.rstrip("\n").split("\t") for l in open(audit) if l.strip() and not l.startswith("#")]
shimmed = set()
if "--shims" in sys.argv:
    # The runtime shim table in toolchain/compat/webcore_ios8_compat.m: { "Class", bool, "selector", ... }
    shimmed = set(re.findall(r'\{\s*"\w+",\s*(?:true|false),\s*"([^"]+)"', open(sys.argv[sys.argv.index("--shims") + 1]).read()))
selectors = [(r[0], r[1]) for r in rows if r[1] not in shimmed]
print("# %d selectors, %d shimmed in compat" % (len(rows), len(rows) - len(selectors)))

files = []
for top in ("WebCore", "WebKitLegacy", "JavaScriptCore", "WTF"):
    for dirpath, dirnames, filenames in os.walk(os.path.join(root, top)):
        dirnames[:] = [d for d in dirnames if d not in ("gtk", "glib", "gstreamer", "win", "wpe", "playstation", "soup", "curl", "skia", "cairo", "mac") or "WebKitLegacy" in dirpath]
        for name in filenames:
            if name.endswith((".mm", ".m", ".h")):
                files.append(os.path.join(dirpath, name))
texts = {}
for path in files:
    try:
        texts[path] = open(path, errors="replace").read()
    except OSError:
        pass

for image, selector in selectors:
    parts = [p for p in selector.split(":") if p] if ":" in selector else [selector]
    first = parts[0]
    kinds = {"guard": [], "@selector": [], "send": []}
    pattern = re.compile(r"\b" + re.escape(first) + (r"\s*:" if ":" in selector else r"\b"))
    for path, text in texts.items():
        if first not in text:
            continue
        for match in pattern.finditer(text):
            start = text.rfind("\n", 0, match.start()) + 1
            end = text.find("\n", match.end())
            line = text[start:end]
            lineno = text.count("\n", 0, match.start()) + 1
            window = text[match.start():match.start() + 300]
            if not all(p in window for p in parts):
                continue
            stripped = line.strip()
            if stripped.startswith(("-", "+")) and ";" not in stripped[:2]:
                continue  # a method declaration or definition
            where = "%s:%d: %s" % (os.path.relpath(path, root), lineno, stripped[:140])
            if "RespondToSelector" in line or "respondsToSelector" in line:
                kinds["guard"].append(where)
            elif "@selector(" in text[max(start, match.start() - 12):match.start()]:
                kinds["@selector"].append(where)
            elif "[" in text[max(0, match.start() - 200):match.start()]:
                kinds["send"].append(where)
    if sends_only and not kinds["send"]:
        continue
    print("%s\t%s\tguard %d, @selector %d, send %d" % (image, selector, len(kinds["guard"]), len(kinds["@selector"]), len(kinds["send"])))
    for where in kinds["send"][:6]:
        print("    send  " + where)
