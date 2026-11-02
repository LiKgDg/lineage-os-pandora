#!/bin/bash
# 一次性构建 WSL 侧的持久 stage 目录（中间态都放这里，不进 /tmp，不进 /mnt/c）。
# 幂等：已存在的产物不会重复生成。
set -u
source "$(dirname "$0")/wsl-common.sh"

echo "STAGE = $STAGE"
mkdir -p "$STAGE/vb"

# 1) stock 分区（从 OTA payload 提取）
for part in vendor_boot vendor_dlkm system_dlkm; do
  if [ ! -f "$STAGE/stock_$part.img" ]; then
    echo "== 提取 stock $part =="
    python3 "$WORK/wsl_extract_part.py" --out "$STAGE" "$part" || exit 9
  else
    echo "== stock $part 已存在 =="
  fi
done

# vendor 是 589 MB，只有 fstab 比对需要；默认不生成，传 --with-vendor 或 WANT_VENDOR=1 才做
if [ "${WANT_VENDOR:-0}" = "1" ] || [ "${1:-}" = "--with-vendor" ]; then
  if [ ! -f "$STAGE/stock_vendor.img" ]; then
    echo "== 提取 stock vendor（589 MB，约 1–2 分钟）=="
    python3 "$WORK/wsl_extract_part.py" --out "$STAGE" vendor || exit 9
  else
    echo "== stock vendor 已存在 =="
  fi
fi

# 2) 两侧 vendor_boot ramdisk -> cpio
#    LOS 源: UotanToolbox images/vendor_boot.img
#    stock 源: $STAGE/stock_vendor_boot.img
build_ramdisk() {
  local side="$1" img="$2" out="$STAGE/${1}_vendor_ramdisk.cpio"
  [ -f "$out" ] && { echo "== $side ramdisk cpio 已存在 =="; return 0; }
  need "$img" "$side vendor_boot 镜像"
  echo "== 解 $side vendor_boot -> cpio =="
  python3 - "$img" "$out" "$WORK" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from bootimg import parse_vendor_boot
from lz4legacy import decompress_any
img, out = sys.argv[1], sys.argv[2]
info = parse_vendor_boot(img)
with open(img, "rb") as f:
    f.seek(info["vendor_ramdisk_off"])
    raw = f.read(info["vendor_ramdisk_size"])
data, how = decompress_any(raw)
with open(out, "wb") as g:
    g.write(data)
print(f"   {len(raw)} -> {len(data)} bytes ({how})")
PY
  need "$out" "$side ramdisk cpio"
}

build_ramdisk los   "$IMGS/vendor_boot.img"
build_ramdisk stock "$STAGE/stock_vendor_boot.img"

# 3) 解开 ramdisk
for side in los stock; do
  if [ ! -d "$STAGE/vb/$side/lib/modules" ]; then
    echo "== 解 $side ramdisk =="
    mkdir -p "$STAGE/vb/$side"
    ( cd "$STAGE/vb/$side" && cpio -idm --quiet < "$STAGE/${side}_vendor_ramdisk.cpio" ) || exit 9
  fi
done

echo
echo "########## stage 就绪 ##########"
du -sh "$STAGE" 2>/dev/null
for side in los stock; do
  echo "  $side vendor_boot: $(find "$STAGE/vb/$side/lib/modules" -name '*.ko' | wc -l) 个 .ko"
done
