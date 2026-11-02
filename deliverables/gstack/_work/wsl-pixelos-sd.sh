#!/bin/bash
# system_dlkm 三份 flatten/版本化清单的差异 + 门禁对 PixelOS 三集合的判定
set -u
SD=/root/work/pixelos/mnt/system_dlkm
LS=/root/work/gstack/mnt/los_system_dlkm
GATE="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/kmi-gate.sh"

echo "########## 1. system_dlkm 四份清单 ##########"
for f in "$SD/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k/modules.load" \
         "$SD/flatten/lib/modules/modules.load" \
         "$LS/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k/modules.load" \
         "$LS/flatten/lib/modules/modules.load"; do
  [ -f "$f" ] && printf '  md5=%s 条目=%-3s %s\n' "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")" "${f#/root/work}"
done

echo
echo "=== PixelOS flatten vs LOS flatten（LOS 独有 / PixelOS 独有） ==="
echo "  -- LOS flatten 独有 --"
comm -23 <(sort -u "$LS/flatten/lib/modules/modules.load") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'
echo "  -- PixelOS flatten 独有 --"
comm -13 <(sort -u "$LS/flatten/lib/modules/modules.load") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'

echo
echo "=== 版本化清单（两侧逐字节相同）vs flatten 清单 的差异 ==="
V="$SD/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k/modules.load"
echo "  -- 只在版本化里 --"
comm -23 <(sort -u "$V") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'
echo "  -- 只在 flatten 里 --"
comm -13 <(sort -u "$V") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'

echo
echo "########## 2. 门禁对 PixelOS 三集合的判定（应全 PASS） ##########"
bash "$GATE" -R -K /root/work/pixelos/boot.img \
  /root/work/pixelos/vb/lib/modules \
  /root/work/pixelos/mnt/vendor_dlkm/lib/modules \
  /root/work/pixelos/mnt/system_dlkm/flatten/lib/modules 2>&1 | tail -22
echo "退出码=$?"
