#!/bin/bash
# PixelOS（同机型、已构建、可启动）的 KMI 取证：内核 banner + 三处模块的 vermagic / CRC
set -u
PXC="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/PixelOS_pandora-17.0-20261102"
WORK="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"
STAGE=/root/work/pixelos
mkdir -p "$STAGE" || exit 9
cd "$STAGE" || exit 9

# --- 1. 备齐镜像（幂等） ---
[ -f boot.img ]        || cp "$PXC/boot.img" .
[ -f vendor_boot.img ] || cp "$PXC/vendor_boot.img" .
for img in vendor_dlkm.img system_dlkm.img; do
  [ -f "$img" ] || { echo "== 从 Fastboot 包解 $img =="; unzip -o -q "$PXC/Fastboot_PixelOS_pandora-17.0-20261102-0424.zip" "$img" -d "$STAGE" || exit 9; }
done
ls -l *.img | awk '{print "  ", $5, $9}'

# --- 2. boot.img 内核 banner ---
echo
echo "########## PixelOS 内核 ##########"
python3 - "$STAGE" "$WORK" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from bootimg import parse_boot
info = parse_boot(sys.argv[1] + "/boot.img")
with open(sys.argv[1] + "/boot.img", "rb") as f:
    f.seek(info["kernel_off"]); k = f.read(info["kernel_size"])
open(sys.argv[1] + "/kernel.bin", "wb").write(k)
print(f"  kernel 大小: {len(k):,} 字节")
i = k.find(b"Linux version")
print("  banner:", k[i:i+120].split(b"\x00")[0].decode("utf-8", "replace") if i >= 0 else "未找到")
PY

# --- 3. vendor_boot ramdisk -> cpio -> 模块 ---
echo
echo "########## vendor_boot ramdisk ##########"
if [ ! -d "$STAGE/vb/lib/modules" ]; then
  python3 - "$STAGE" "$WORK" <<'PY'
import sys
sys.path.insert(0, sys.argv[2])
from bootimg import parse_vendor_boot
from lz4legacy import decompress_legacy
st = sys.argv[1]
info = parse_vendor_boot(st + "/vendor_boot.img")
print(f"  header_version={info['header_version']} page={info['page_size']} "
      f"vendor_ramdisk_size={info['vendor_ramdisk_size']:,} dtb_size={info['dtb_size']:,}")
with open(st + "/vendor_boot.img", "rb") as f:
    f.seek(info["vendor_ramdisk_off"]); raw = f.read(info["vendor_ramdisk_size"])
print("  ramdisk magic:", raw[:4].hex())
if raw[:4] == b"\x02\x21\x4c\x18":
    data, blocks = decompress_legacy(raw)
    print(f"  ramdisk {len(raw):,} -> {len(data):,} 字节（{blocks} 个 LZ4 legacy block）")
else:
    data = raw
    print(f"  ramdisk {len(raw):,} 字节（未压缩）")
open(st + "/vb.cpio", "wb").write(data)
PY
  mkdir -p "$STAGE/vb"
  ( cd "$STAGE/vb" && cpio -idm --quiet < "$STAGE/vb.cpio" ) || exit 9
fi
[ -d "$STAGE/vb/lib/modules" ] || { echo "FATAL: ramdisk 内没有 lib/modules"; exit 9; }

# --- 4. 三处模块的 vermagic / CRC 统计 ---
scan() {
  local tag="$1" dir="$2"
  local n; n=$(find "$dir" -name '*.ko' -type f | wc -l)
  echo "  ---- $tag: $n 个 .ko ----"
  [ "$n" -eq 0 ] && return
  find "$dir" -name '*.ko' -type f -print0 | xargs -0 -n1 -P8 sh -c '
    v=$(modinfo -F vermagic "$0" 2>/dev/null | awk "{print \$1}")
    c=$(modprobe --dump-modversions "$0" 2>/dev/null | awk "/module_layout/{print \$1}")
    echo "${v:-NOVERMAGIC} ${c:-NOCRC}"
  ' | sort | uniq -c | sort -rn | sed 's/^/     /'
}

echo
echo "########## 模块世代 ##########"
echo "== PixelOS vendor_boot =="
scan "vendor_boot" "$STAGE/vb/lib/modules"

for part in vendor_dlkm system_dlkm; do
  mnt="$STAGE/mnt/$part"
  mkdir -p "$mnt"
  if ! mountpoint -q "$mnt"; then
    if ! mount -o loop,ro "$STAGE/$part.img" "$mnt" 2>/dev/null; then
      echo "  !! $part 挂载失败（非 ext4？）"
      continue
    fi
  fi
  echo "== PixelOS $part =="
  # system_dlkm 有版本化目录 + flatten 副本，分开统计
  if [ "$part" = "system_dlkm" ]; then
    for sub in "" "flatten/"; do
      d="$mnt/${sub}lib/modules"
      [ -d "$d" ] || continue
      scan "$part/${sub:-<versioned>}" "$d"
    done
  else
    scan "$part" "$mnt/lib/modules"
  fi
done
