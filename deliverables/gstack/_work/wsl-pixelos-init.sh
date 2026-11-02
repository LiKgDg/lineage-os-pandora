#!/bin/bash
# init_boot / dtbo 比对：PixelOS vs LOS
set -u
PX=/root/work/pixelos
GS=/root/work/gstack
LOSIMG="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
WORK="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"

echo "########## 1. dtbo.img ##########"
cp -n "$LOSIMG/dtbo.img" "$GS/los_dtbo.img" 2>/dev/null || true
cp -n "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/PixelOS_pandora-17.0-20261102/dtbo.img" "$PX/dtbo.img" 2>/dev/null || true
for f in "$GS/los_dtbo.img" "$PX/dtbo.img"; do
  [ -f "$f" ] && printf '  %-28s %s  %s\n' "$(basename "$f")" "$(sha256sum "$f" | cut -c1-16)" "$(stat -c%s "$f")"
done
cmp -s "$GS/los_dtbo.img" "$PX/dtbo.img" && echo "  => 逐字节相同" || echo "  => 不同"

echo
echo "########## 2. init_boot.img ##########"
cp -n "$LOSIMG/init_boot.img" "$GS/los_init_boot.img" 2>/dev/null || true
cp -n "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/PixelOS_pandora-17.0-20261102/init_boot.img" "$PX/init_boot.img" 2>/dev/null || true
for tag in los px; do
  img=$([ "$tag" = los ] && echo "$GS/los_init_boot.img" || echo "$PX/init_boot.img")
  [ -f "$img" ] || continue
  echo "  == $tag =="
  python3 - "$img" "$WORK" "$tag" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[2])
from bootimg import parse_boot
img, tag = sys.argv[1], sys.argv[3]
i = parse_boot(img)
print(f"    kernel_size={i['kernel_size']:,} ramdisk_size={i['ramdisk_size']:,}")
with open(img, "rb") as f:
    f.seek(i["ramdisk_off"]); raw = f.read(i["ramdisk_size"])
print(f"    ramdisk magic={raw[:4].hex()} ({len(raw):,} 字节)")
out = f"/root/work/pixelos/init_{tag}.cpio"
if raw[:4] in (b"\x1f\x8b",):
    import gzip
    open(out, "wb").write(gzip.decompress(raw)); print("    gzip 解压")
elif raw[:4] == b"\x02\x21\x4c\x18":
    from lz4legacy import decompress_legacy
    d, b = decompress_legacy(raw); open(out, "wb").write(d); print(f"    lz4 解压 {b} blocks")
else:
    open(out, "wb").write(raw); print("    未压缩")
PY
done

echo
echo "  == init ramdisk 文件清单比对 =="
for tag in los px; do
  d=/root/work/pixelos/init_$tag
  [ -d "$d" ] || { mkdir -p "$d"; ( cd "$d" && cpio -idm --quiet < "/root/work/pixelos/init_$tag.cpio" ) 2>/dev/null; }
done
python3 - <<'PY'
import os, hashlib
def walk(r):
    o = {}
    for dp, _, fs in os.walk(r):
        for f in fs:
            p = os.path.join(dp, f); o[os.path.relpath(p, r)] = p
    return o
def dg(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""): h.update(c)
    return h.hexdigest()
A, B = walk("/root/work/pixelos/init_px"), walk("/root/work/pixelos/init_los")
print(f"    PixelOS {len(A)} 文件，LOS {len(B)} 文件")
print(f"    仅 PixelOS: {sorted(set(A)-set(B)) or '无'}")
print(f"    仅 LOS    : {sorted(set(B)-set(A)) or '无'}")
common = sorted(set(A) & set(B))
diff = [n for n in common if dg(A[n]) != dg(B[n])]
print(f"    共有 {len(common)}，相同 {len(common)-len(diff)}，不同 {len(diff)}")
for n in diff[:15]: print(f"      DIFF {n}")
PY
