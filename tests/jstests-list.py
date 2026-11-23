#!/usr/bin/env python3
# Build a jscrun list (file<TAB>opt<TAB>opt...) from JSTests/stress: honour the //@ directives that matter on a
# 32-bit, memory-limited, FTL-less, wasm-less device and keep the options tests require.
#   jstests-list.py <JSTests/stress dir> > list.txt
import os
import re
import sys

SKIP_IF = re.compile(r'memoryLimited|addressBits|jitTests|isFTLEnabled|\$architecture\s*!=|wasm', re.I)
OPTION = re.compile(r'"([^"]*)"')
# Conditions that hold on the device; directives guarded by anything else are ignored.
DEVICE_CONDITION = re.compile(r'\s+if\s+\$memoryLimited\s*$')

def directives(path):
    with open(path, errors='replace') as f:
        for line in f:
            if line.startswith('//@'):
                yield line[3:].strip()

def main(root):
    for name in sorted(os.listdir(root)):
        if not name.endswith('.js'):
            continue
        ds = list(directives(os.path.join(root, name)))
        skip = False
        options = []
        runs = []
        for d in ds:
            body = d.split('#')[0].strip()
            if body == 'skip' or body.startswith('slow!'):
                skip = True
            elif body.startswith('skip if') and SKIP_IF.search(body):
                skip = True
            elif 'wasm' in body.lower() or 'FTL' in body and not body.startswith('skip'):
                runs.append(body)
            if body.startswith(('requireOptions', 'runDefault', 'run(')):
                if ' if ' in body and not DEVICE_CONDITION.search(body):
                    continue
                found = OPTION.findall(body)
                options += found[1:] if body.startswith('run(') else found  # run("name", opts...)
        # Tests that only run in FTL/wasm modes have nothing to exercise here.
        if runs and not any(d.startswith(('runDefault', 'run ', 'run(', 'requireOptions')) for d in ds):
            skip = True
        if any('useWasm' in o or 'useFTL' in o for o in options):
            skip = True
        with open(os.path.join(root, name), errors='replace') as f:
            if 'WebAssembly' in f.read():  # wasm is off on armv7
                skip = True
        if not skip:
            print('\t'.join([name] + options))

main(sys.argv[1])
