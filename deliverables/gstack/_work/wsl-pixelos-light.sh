#!/bin/bash
# 轻量对照：vendor_boot 内 dtb 段哈希 + init_boot ramdisk 文件清单
set -u
PX=/root/work/pixelos
GS=/root/work/gstack
WORK="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"
LOSIMG="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"

echo "########## 1. vendor_boot 内 dtb 段 ##########"
python3 - "$PX/vendor_boot.img" "$LOSIMG/vendor_boot.img" "$WORK" <<'PY'
import sys, hashlib
sys.path.insert(0, sys.argv[3])
from bootimg import parse_vendor_boot
for tag, p in (("PixelOS", sys.argv[1]), ("LOS", sys.argv[2])):
    i = parse_vendor_boot(p)
    with open(p, "rb") as f:
        f.seek(i["dtb_off"]); d = f.read(i["dtb_size"])
    print(f"  {tag}: {len(d):,} 字节  sha256={hashlib.sha256(d).hexdigest()[:16]}")
PY

echo
echo "########## 2. init_boot ramdisk 文件清单 ##########"
python3 - "$PX/init_boot.img" "$LOSIMG/init_boot.img" "$WORK" <<'PY'
import sys, gzip, io, os
sys.path.insert(0, sys.argv[3])
from bootimg import parse_boot

def cpio_names(buf):
    names, off = [], 0
    while off + 110 <= len(buf):
        hdr = buf[off:off+110]
        if hdr[:6] != b"070701":
            break
        def f(i): return int(hdr[i:i+8], 16)
        namesize, filesize = f(94), f(54)
        name = buf[off+110:off+110+namesize-1].decode("utf-8", "replace")
        names.append(name)
        off += 110 + namesize
        off += (-off) % 4
        off += filesize
        off += (-off) % 4
    return names

for tag, p in (("PixelOS", sys.argv[1]), ("LOS", sys.argv[2])):
    i = parse_boot(p)
    with open(p, "rb") as f:
        f.seek(i["ramdisk_off"]); raw = f.read(i["ramdisk_size"])
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    n = cpio_names(raw)
    print(f"  {tag}: ramdisk {i['ramdisk_size']:,} 字节，cpio {len(n)} 条目")
    print(f"    顶层: {sorted({x.split('/')[0] for x in n if x})[:8]}")
PY
