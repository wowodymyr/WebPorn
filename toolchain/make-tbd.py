#!/usr/bin/env python3
# Write a TAPI v4 .tbd link stub for one image of a device's shared cache, from the
# export list dsc-exports.py produced. Linking against it records the device's real
# install name (e.g. IOSurface lives in PrivateFrameworks on iOS 8, not where newer
# SDKs put it) and only the symbols that device actually exports.
#   make-tbd.py <exports.tsv> <install-name> <arch> <out.tbd>
import sys

def main(exports, install_name, arch, out):
    symbols, classes, ivars = set(), set(), set()
    with open(exports) as f:
        for line in f:
            image, _, symbol = line.rstrip('\n').partition('\t')
            if image != install_name:
                continue
            if symbol.startswith('_OBJC_CLASS_$_'):
                classes.add(symbol[len('_OBJC_CLASS_$_'):])
            elif symbol.startswith('_OBJC_METACLASS_$_'):
                classes.add(symbol[len('_OBJC_METACLASS_$_'):])
            elif symbol.startswith('_OBJC_IVAR_$_'):
                ivars.add(symbol[len('_OBJC_IVAR_$_'):])
            else:
                symbols.add(symbol)
    if not (symbols or classes):
        sys.exit(f'{install_name}: no exports in {exports}')

    def block(key, names):
        if not names:
            return ''
        return f'    {key}: [ ' + ', '.join(f"'{n}'" for n in sorted(names)) + ' ]\n'

    target = f'{arch}-ios'
    with open(out, 'w') as f:
        f.write('--- !tapi-tbd\ntbd-version: 4\n')
        f.write(f'targets: [ {target} ]\n')
        f.write(f"install-name: '{install_name}'\n")
        f.write(f'exports:\n  - targets: [ {target} ]\n')
        f.write(block('symbols', symbols) + block('objc-classes', classes) + block('objc-ivars', ivars))
        f.write('...\n')

main(*sys.argv[1:])
