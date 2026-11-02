#!/bin/bash
# 原子执行：挂载 → 四份清单对账 → 门禁判定（WSL 重启会掉 loop 挂载，必须一次跑完）
set -u
PX=/root/work/pixelos
GS=/root/work/gstack
LOSIMG="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
GATE="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/kmi-gate.sh"

for pair in "pixelos_sd:$PX/system_dlkm.img:$PX/mnt/system_dlkm" \
            "pixelos_vd:$PX/vendor_dlkm.img:$PX/mnt/vendor_dlkm" \
            "los_sd:$LOSIMG/system_dlkm.img:$GS/mnt/los_system_dlkm" \
            "los_vd:$LOSIMG/vendor_dlkm.img:$GS/mnt/los_vendor_dlkm"; do
  IFS=: read -r tag img mnt <<< "$pair"
  mkdir -p "$mnt"
  mountpoint -q "$mnt" || mount -o loop,ro "$img" "$mnt" 2>/dev/null || echo "  !! $tag 挂载失败"
done
# 只保留本次需要的挂载，旧的残留先卸
for d in "$GS/mnt/stock_vendor_dlkm"; do mountpoint -q "$d" && umount "$d"; done

SD=$PX/mnt/system_dlkm
LS=$GS/mnt/los_system_dlkm
VREL=6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k

echo "########## 1. system_dlkm 四份清单 ##########"
i=0
for f in "$SD/lib/modules/$VREL/modules.load" "$SD/flatten/lib/modules/modules.load" \
         "$LS/lib/modules/$VREL/modules.load" "$LS/flatten/lib/modules/modules.load"; do
  i=$((i+1))
  if [ -f "$f" ]; then
    printf '  %d) md5=%s 条目=%-3s %s\n' "$i" "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")" "${f#/root/work}"
  else
    printf '  %d) 缺失: %s\n' "$i" "$f"
  fi
done

echo
echo "=== LOS flatten 独有 vs PixelOS flatten ==="
comm -23 <(sort -u "$LS/flatten/lib/modules/modules.load") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'
echo "=== PixelOS flatten 独有 vs LOS flatten ==="
comm -13 <(sort -u "$LS/flatten/lib/modules/modules.load") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'

echo
echo "=== 版本化清单 vs PixelOS flatten 清单 ==="
echo "  -- 只在版本化 --"; comm -23 <(sort -u "$SD/lib/modules/$VREL/modules.load") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'
echo "  -- 只在 flatten --"; comm -13 <(sort -u "$SD/lib/modules/$VREL/modules.load") <(sort -u "$SD/flatten/lib/modules/modules.load") | sed 's/^/    /'

echo
echo "########## 2. 门禁：PixelOS 三集合（期望全 PASS） ##########"
bash "$GATE" -R -K "$PX/boot.img" -q \
  "$PX/vb/lib/modules" "$SD/flatten/lib/modules" "$SD/lib/modules/$VREL" >/tmp/px-gate.log 2>&1
echo "  退出码=$?"
sed -n '/汇总/,$p' /tmp/px-gate.log | sed 's/^/  /'

echo
echo "########## 3. 门禁：LOS 三集合（期望 FAIL） ##########"
bash "$GATE" -R -q \
  "$GS/vb/los/lib/modules" "$LS/flatten/lib/modules" "$LS/lib/modules/$VREL" >/tmp/los-gate.log 2>&1
echo "  退出码=$?"
sed -n '/汇总/,$p' /tmp/los-gate.log | sed 's/^/  /'
