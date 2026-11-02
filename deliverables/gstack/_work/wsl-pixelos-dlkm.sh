#!/bin/bash
# PixelOS 的 vendor_dlkm / system_dlkm 与 stock、LOS 的字节关系
set -u
PX=/root/work/pixelos
GS=/root/work/gstack
LOSIMG="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"

# LOS 的 dlkm 镜像（幂等挂载）
for p in vendor_dlkm system_dlkm; do
  mnt=$GS/mnt/los_$p; mkdir -p "$mnt"
  mountpoint -q "$mnt" || mount -o loop,ro "$LOSIMG/$p.img" "$mnt" 2>/dev/null || { echo "FATAL: 挂载 LOS $p 失败"; exit 9; }
  mnt2=$PX/mnt/$p; mkdir -p "$mnt2"
  mountpoint -q "$mnt2" || mount -o loop,ro "$PX/$p.img" "$mnt2" 2>/dev/null || { echo "FATAL: 挂载 PixelOS $p 失败"; exit 9; }
done
mnts=$GS/mnt/stock_vendor_dlkm; mkdir -p "$mnts"
mountpoint -q "$mnts" || mount -t erofs -o loop,ro "$GS/stock_vendor_dlkm.img" "$mnts" 2>/dev/null || echo "  (stock vendor_dlkm 挂载失败，跳过)"

cmp_tree() {   # cmp_tree <label> <dirA> <dirB>
  python3 - "$1" "$2" "$3" <<'PY'
import sys, os, hashlib
label, A, B = sys.argv[1:4]
def walk(root):
    out = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            if f.endswith(".ko"):
                p = os.path.join(dp, f)
                out[f] = p
    return out
def dg(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()
a, b = walk(A), walk(B)
if not a or not b:
    print(f"  {label}: 一侧为空 (A={len(a)} B={len(b)})，跳过")
    sys.exit()
common = sorted(set(a) & set(b))
same = sum(1 for n in common if dg(a[n]) == dg(b[n]))
print(f"  {label}: A={len(a)} B={len(b)} 同名={len(common)} 相同={same} 不同={len(common)-same} A独有={len(set(a)-set(b))} B独有={len(set(b)-set(a))}")
PY
}

echo "########## vendor_dlkm ##########"
cmp_tree "PixelOS vs stock" "$PX/mnt/vendor_dlkm/lib/modules" "$mnts/lib/modules"
cmp_tree "PixelOS vs LOS  " "$PX/mnt/vendor_dlkm/lib/modules" "$GS/mnt/los_vendor_dlkm/lib/modules"

echo
echo "########## system_dlkm ##########"
cmp_tree "PixelOS(版本化) vs LOS(版本化)" "$PX/mnt/system_dlkm/lib/modules" "$GS/mnt/los_system_dlkm/lib/modules"
cmp_tree "PixelOS(flatten) vs LOS(flatten)" "$PX/mnt/system_dlkm/flatten/lib/modules" "$GS/mnt/los_system_dlkm/flatten/lib/modules"
cmp_tree "PixelOS 版本化 vs PixelOS flatten" "$PX/mnt/system_dlkm/lib/modules" "$PX/mnt/system_dlkm/flatten/lib/modules"
cmp_tree "LOS 版本化 vs LOS flatten    " "$GS/mnt/los_system_dlkm/lib/modules" "$GS/mnt/los_system_dlkm/flatten/lib/modules"

echo
echo "########## modules.load 清单 ##########"
for tag in "PixelOS_vd:$PX/mnt/vendor_dlkm" "LOS_vd:$GS/mnt/los_vendor_dlkm" "PixelOS_sdflat:$PX/mnt/system_dlkm/flatten" "LOS_sdflat:$GS/mnt/los_system_dlkm/flatten" "PixelOS_sdver:$PX/mnt/system_dlkm" "LOS_sdver:$GS/mnt/los_system_dlkm"; do
  name=${tag%%:*}; dir=${tag#*:}
  f=$(find "$dir" -maxdepth 2 -name 'modules.load' 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    t=$(grep -c . "$f"); u=$(sort -u "$f" | grep -c .)
    printf "  %-16s %-5s 条目 %-4s 唯一 %-4s\n" "$name" "$(md5sum "$f" | cut -c1-8)" "$t" "$u"
  else
    printf "  %-16s 无 modules.load\n" "$name"
  fi
done
