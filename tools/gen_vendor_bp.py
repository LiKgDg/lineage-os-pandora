#!/usr/bin/env python3
"""Generate a soong (Android.bp) blob package from proprietary-files.txt.

Modern LineageOS blob packages are soong-based; a make-based Android.mk
collides with soong's per-partition NOTICE.xml.gz target:

    build/make/core/base_rules.mk:513: error: overriding commands for target
    out/target/product/pandora/odm/etc/NOTICE.xml.gz

Usage:
    gen_vendor_bp.py <device_vendor_dir>
"""

import json
import os
import re
import sys


def sanitize(s):
    return re.sub(r"[^A-Za-z0-9_]", "_", s)


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def part_flags(part):
    if part == "vendor":
        return ["vendor: true"]
    if part == "odm":
        return ["soc_specific: true"]
    if part == "system_ext":
        return ["system_ext_specific: true"]
    return []


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    base = sys.argv[1]
    entries = [
        l.strip()
        for l in open(os.path.join(base, "proprietary-files.txt"))
        if l.strip() and not l.startswith("#")
    ]

    blocks = []
    modules = []
    seen = set()

    for entry in entries:
        raw = entry.lstrip("-")
        parts = raw.split("/")
        if len(parts) < 3 or parts[0] not in ("vendor", "odm", "system_ext"):
            continue
        part, rel = parts[0], "/".join(parts[1:])
        src = os.path.join(base, "proprietary", part, rel)
        if not os.path.isfile(src):
            continue

        fname = os.path.basename(rel)
        # build artifacts / licence files must never be imported as blobs
        if fname.startswith("NOTICE"):
            continue
        subdir = os.path.dirname(rel)
        flags = part_flags(part)
        name = sanitize("blob_%s_%s" % (part, rel))
        if name in seen:
            continue
        seen.add(name)

        low = fname.lower()
        if low.endswith(".so"):
            body = [
                "cc_prebuilt_library_shared {",
                '    name: "%s",' % name,
                '    owner: "xiaomi",',
                '    strip: { none: true },',
                '    check_elf_files: false,',
                '    compile_multilib: "%s",' % ("64" if rel.startswith("lib64") else "32"),
                '    stem: "%s",' % fname[:-3],
                '    srcs: ["proprietary/%s/%s"],' % (part, rel),
            ]
            if subdir and subdir not in ("lib", "lib64"):
                body.append('    relative_install_path: "%s",' % subdir.replace("lib64/", "").replace("lib/", ""))
            body += ["    " + f + "," for f in flags]
            body.append("}")
            blocks.append("\n".join(body))
        elif low.endswith(".apk"):
            # android_app_import has no 'stem' property, so the module name must
            # be the desired installed filename. Overlay APKs live outside
            # app/priv-app and are skipped for now (needs runtime_resource_overlay).
            if "/overlay/" in rel or rel.startswith("overlay/"):
                continue
            app_name = sanitize(fname[:-4])
            if app_name in seen:
                continue
            seen.add(app_name)
            name = app_name
            body = [
                "android_app_import {",
                '    name: "%s",' % app_name,
                '    owner: "xiaomi",',
                "    presigned: true,",
                "    dex_preopt: { enabled: false },",
                '    apk: "proprietary/%s/%s",' % (part, rel),
            ]
            if "/priv-app/" in rel:
                body.append("    privileged: true,")
            body += ["    " + f + "," for f in flags]
            body.append("}")
            blocks.append("\n".join(body))
        elif is_elf(src):
            body = [
                "cc_prebuilt_binary {",
                '    name: "%s",' % name,
                '    owner: "xiaomi",',
                '    strip: { none: true },',
                '    check_elf_files: false,',
                '    stem: "%s",' % fname,
                '    srcs: ["proprietary/%s/%s"],' % (part, rel),
            ]
            if subdir and subdir != "bin":
                body.append('    relative_install_path: "%s",' % subdir)
            body += ["    " + f + "," for f in flags]
            body.append("}")
            blocks.append("\n".join(body))
        else:
            body = [
                "prebuilt_etc {",
                '    name: "%s",' % name,
                '    owner: "xiaomi",',
                "    filename_from_src: true,",
                '    src: "proprietary/%s/%s",' % (part, rel),
            ]
            if subdir and subdir != "etc":
                sd = subdir[4:] if subdir.startswith("etc/") else subdir
                if sd:
                    body.append('    sub_dir: "%s",' % sd)
            body += ["    " + f + "," for f in flags]
            body.append("}")
            blocks.append("\n".join(body))

        modules.append(name)

    with open(os.path.join(base, "Android.bp"), "w") as f:
        f.write("// Auto-generated by tools/gen_vendor_bp.py -- NOT build-verified.\n")
        f.write("// Source: proprietary-files.txt derived from the official payload dump.\n\n")
        f.write("\n\n".join(blocks))
        f.write("\n")

    with open(os.path.join(base, "pandora-vendor.mk"), "w") as f:
        f.write("# Auto-generated by tools/gen_vendor_bp.py\n\n")
        f.write("PRODUCT_SOONG_NAMESPACES += vendor/xiaomi/pandora\n\n")
        f.write("PRODUCT_PACKAGES += \\\n")
        for i, m in enumerate(modules):
            sep = " \\" if i < len(modules) - 1 else ""
            f.write("    %s%s\n" % (m, sep))

    # make-based package must not coexist with the soong one
    mk = os.path.join(base, "Android.mk")
    if os.path.exists(mk):
        os.rename(mk, mk + ".disabled_by_pandora")

    print("modules=%d" % len(modules))


if __name__ == "__main__":
    main()
