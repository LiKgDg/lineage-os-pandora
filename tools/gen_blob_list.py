#!/usr/bin/env python3
"""Generate a LineageOS-style proprietary blob package from stock partition trees.

Usage:
    gen_blob_list.py <out_device_vendor_dir> <partition>=<mountpoint> [...]

Example:
    gen_blob_list.py /root/android/lineage/vendor/xiaomi/pandora \
        vendor=/mnt/pv odm=/mnt/po system_ext=/mnt/pse

Produces:
    <out>/proprietary-files.txt      LineageOS blob list ('-' prefix = strip)
    <out>/proprietary/<part>/...     copied blobs (symlinks preserved as .link files)
    <out>/blob-stats.txt             size / class breakdown
"""

import os
import shutil
import sys

ELF_MAGIC = b"\x7fELF"


def is_elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == ELF_MAGIC
    except OSError:
        return False


def classify(path, rel):
    """Rough blob class, used only for statistics."""
    ext = os.path.splitext(path)[1].lower()
    if ext == ".so":
        return "shared_lib"
    if ext in (".apk", ".apex"):
        return ext[1:]
    if ext in (".jar",):
        return "jar"
    if is_elf(path):
        return "executable"
    if ext in (".bin", ".mbn", ".elf", ".mdt", ".b0", ".b00", ".fw", ".img"):
        return "firmware"
    return "etc"


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    out_dir = sys.argv[1]
    parts = []
    for spec in sys.argv[2:]:
        name, _, mp = spec.partition("=")
        parts.append((name, mp))

    prop_dir = os.path.join(out_dir, "proprietary")
    os.makedirs(prop_dir, exist_ok=True)

    lines = []
    stats = {}
    total_bytes = 0
    n_files = 0
    n_links = 0

    for name, mp in parts:
        if not os.path.isdir(mp):
            print("skip missing mountpoint %s" % mp)
            continue
        for root, dirs, files in os.walk(mp):
            dirs.sort()
            for fn in sorted(files):
                src = os.path.join(root, fn)
                rel = os.path.relpath(src, mp)
                entry = "%s/%s" % (name, rel)
                dst = os.path.join(prop_dir, name, rel)
                os.makedirs(os.path.dirname(dst), exist_ok=True)

                if os.path.islink(src):
                    # record symlink target; Android.mk side handles it
                    tgt = os.readlink(src)
                    with open(dst + ".link", "w") as f:
                        f.write(tgt)
                    lines.append(entry)
                    stats["symlink"] = stats.get("symlink", 0) + 1
                    n_links += 1
                    continue

                if not os.path.isfile(src):
                    continue

                shutil.copy2(src, dst)
                size = os.path.getsize(dst)
                total_bytes += size
                n_files += 1

                cls = classify(src, rel)
                stats[cls] = stats.get(cls, 0) + 1
                # '-' prefix tells extract-utils to strip the ELF before packaging
                if cls in ("shared_lib", "executable"):
                    lines.append("-" + entry)
                else:
                    lines.append(entry)

    lines.sort(key=lambda s: s.lstrip("-"))
    with open(os.path.join(out_dir, "proprietary-files.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")

    with open(os.path.join(out_dir, "blob-stats.txt"), "w") as f:
        f.write("files copied : %d\n" % n_files)
        f.write("symlinks     : %d\n" % n_links)
        f.write("total bytes  : %d (%.2f GiB)\n" % (total_bytes, total_bytes / 2**30))
        f.write("entries      : %d\n\n" % len(lines))
        for k in sorted(stats):
            f.write("%-12s %d\n" % (k, stats[k]))

    print("entries=%d files=%d symlinks=%d bytes=%d" % (len(lines), n_files, n_links, total_bytes))
    for k in sorted(stats):
        print("  %-12s %d" % (k, stats[k]))


if __name__ == "__main__":
    main()
