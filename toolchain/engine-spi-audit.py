#!/usr/bin/env python3
"""List selectors that system code sends to the old engine and the new one lacks.

  engine-spi-audit.py <dyld_shared_cache> <new-engine-macho>... -- <consumer>...

A consumer is a shared-cache install path (/System/Library/Frameworks/UIKit.framework/UIKit)
or an app binary on disk. Reported: selectors in a consumer's __objc_selrefs that the
old WebKitLegacy / WebCore / JavaScriptCore implement and no new-engine image does.
Those are engine SPI the app still calls after the swap (Safari's
-[WebPreferences _setLayoutInterval:]): each needs a shim or a no-op. The last column
but one says whether some other system image implements the selector too, in which
case the receiver may not be an engine object at all; the last lists the old classes
(-instance / +class method, (Category)) that implement it.
"""
import importlib.util, os, struct, sys

spec = importlib.util.spec_from_file_location("audit", os.path.join(os.path.dirname(__file__), "objc-selector-audit.py"))
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

OLD_ENGINE = ("/System/Library/PrivateFrameworks/WebKitLegacy.framework/WebKitLegacy",
              "/System/Library/PrivateFrameworks/WebCore.framework/WebCore",
              "/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore")


def cache_paths(path):
    with open(path, "rb") as f:
        head = f.read(32)
        _, _, images_off, images_count = struct.unpack_from("<IIII", head, 16)
        f.seek(images_off)
        infos = f.read(32 * images_count)
        paths = []
        for i in range(images_count):
            f.seek(struct.unpack_from("<I", infos, 32 * i + 24)[0])
            paths.append(f.read(256).split(b"\0", 1)[0].decode())
    return paths


def class_name(image, cls):
    ro = image.follow(cls + 4 * image.ptr, lambda a: image.is_class_ro(a & image.data_mask)) & image.data_mask
    return image.selector_at(image.follow(ro + image.ro_name_offset(), image.selector_at)) if ro else "?"


def owners(image):
    """selector -> {"-[Class]", "+[Class]", "(Category)"} for the classes and categories of an image."""
    result = {}
    for addr, size in image.sections.get("__objc_classlist", []):
        for slot in range(addr, addr + size, image.ptr):
            try:
                cls = image.follow(slot, image.is_class)
                name = class_name(image, cls)
                for sel in image.class_methods(cls):
                    result.setdefault(sel, set()).add("-" + name)
                for sel in image.class_methods(image.follow(cls, image.is_class)):
                    result.setdefault(sel, set()).add("+" + name)
            except (ValueError, struct.error):
                pass
    for addr, size in image.sections.get("__objc_catlist", []):
        for slot in range(addr, addr + size, image.ptr):
            try:
                cat = image.follow(slot, lambda a: image.follow(a, image.selector_at) != 0)
                name = image.selector_at(image.follow(cat, image.selector_at))
                for field, kind in ((2, "-"), (3, "+")):
                    for sel in image.method_names(image.follow(cat + field * image.ptr, image.is_method_list)):
                        result.setdefault(sel, set()).add(kind + "(" + name + ")")
            except (ValueError, struct.error):
                pass
    return result


def main(argv):
    split = argv.index("--")
    cache, new_machos, consumers = argv[0], argv[1:split], argv[split + 1:]
    images = dict(zip(cache_paths(cache), audit.cache_images(cache)))
    old_owners = {}
    for p in OLD_ENGINE:
        for sel, where in owners(images[p]).items():
            old_owners.setdefault(sel, set()).update(where)
    old = set(old_owners)
    others = set()
    for path, image in images.items():
        if path not in OLD_ENGINE:
            others |= image.implemented()
    new = set().union(*(audit.file_image(m).implemented() for m in new_machos))
    for consumer in consumers:
        image = images.get(consumer) or audit.file_image(consumer)
        missing = sorted((image.selrefs() & old) - new)
        print(f"# {consumer}: {len(missing)}", file=sys.stderr)
        for sel in missing:
            print(f"{consumer.rsplit('/', 1)[-1]}\t{sel}\t{'also-system' if sel in others else 'engine-only'}\t{' '.join(sorted(old_owners[sel]))}")


if __name__ == "__main__":
    main(sys.argv[1:])
