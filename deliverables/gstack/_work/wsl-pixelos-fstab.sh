#!/bin/bash
# PixelOS vs LOS：fstab / cmdline / dtb / ramdisk 结构对照
set -u
PX=/root/work/pixelos
GS=/root/work/gstack
LOSIMG="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
WORK="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"

echo "########## 1. vendor_boot 头与 cmdline ##########"
python3 - "$PX/vendor_boot.img" "$LOSIMG/vendor_boot.img" "$WORK" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from bootimg import parse_vendor_boot
for tag, p in (("PixelOS", sys.argv[1]), ("LOS", sys.argv[2])):
    i = parse_vendor_boot(p)
    print(f"  {tag}: hdr={i['header_version']} ramdisk={i['vendor_ramdisk_size']:,} "
          f"dtb={i['dtb_size']:,} bootconfig={i.get('bootconfig_size', 0):,}")
    print(f"    cmdline: {i['cmdline'][:160]}")
PY

echo
echo "########## 2. first_stage fstab 的 userdata / metadata 行 ##########"
for tag in PixelOS LOS; do
  f=$([ "$tag" = PixelOS ] && echo "$PX/vb/first_stage_ramdisk/fstab.qcom" || echo "$GS/vb/los/first_stage_ramdisk/fstab.qcom")
  if [ -f "$f" ]; then
    echo "  == $tag ($(stat -c%s "$f") 字节, sha256 $(sha256sum "$f" | cut -c1-12)) =="
    grep -E "by-name/(userdata|metadata)" "$f" | sed 's/^/    /'
  else
    echo "  == $tag: 无 first_stage_ramdisk/fstab.qcom =="
    find "$(dirname "$f")" -name 'fstab*' 2>/dev/null | sed 's/^/    /'
  fi
done

echo
echo "########## 3. userdata 行 token 级差集 ##########"
python3 - "$PX/vb/first_stage_ramdisk/fstab.qcom" "$GS/vb/los/first_stage_ramdisk/fstab.qcom" <<'PY'
import sys
def ud(p):
    for line in open(p, encoding="utf-8", errors="replace"):
        if "by-name/userdata" in line and not line.strip().startswith("#"):
            f = line.split()
            opts = set()
            for col in f[3:5]:
                opts |= {t for t in col.split(",") if t}
            return opts, line.strip()
    return set(), ""
a, la = ud(sys.argv[1])
b, lb = ud(sys.argv[2])
print("  PixelOS 独有:", sorted(a - b) or "（无）")
print("  LOS 独有    :", sorted(b - a) or "（无）")
print("  共有 token 数:", len(a & b))
PY

echo
echo "########## 4. ramdisk 顶层结构差异 ##########"
diff <(cd "$PX/vb" && find . -maxdepth 2 -type d | sort) <(cd "$GS/vb/los" && find . -maxdepth 2 -type d | sort) | head -20
echo "  （无输出=目录结构一致）"
