#!/bin/bash
# vendor_dlkm 的 modules.load 对账：PixelOS vs LOS
set -u
P=/root/work/pixelos/mnt/vendor_dlkm/lib/modules/modules.load
L=/root/work/gstack/mnt/los_vendor_dlkm/lib/modules/modules.load
for f in "$P" "$L"; do
  [ -f "$f" ] || { echo "FATAL: 缺 $f"; exit 9; }
  printf '%-58s md5=%s 条目=%s 唯一=%s\n' "$f" "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")" "$(sort -u "$f" | grep -c .)"
done

echo
echo "=== LOS 独有（PixelOS 没有的条目） ==="
comm -23 <(sort -u "$L") <(sort -u "$P") | sed 's/^/  /'
echo
echo "=== PixelOS 独有（LOS 缺的条目） ==="
comm -13 <(sort -u "$L") <(sort -u "$P") | sed 's/^/  /'

echo
echo "=== LOS 清单里哪些文件在本分区不存在（悬空） ==="
while read -r m; do
  [ -z "$m" ] && continue
  [ -f "/root/work/gstack/mnt/los_vendor_dlkm/lib/modules/$m" ] || echo "  $m"
done < <(sort -u "$L")

echo
echo "=== system_dlkm flatten 的 modules.load ==="
for f in /root/work/pixelos/mnt/system_dlkm/flatten/lib/modules/modules.load \
         /root/work/gstack/mnt/los_system_dlkm/flatten/lib/modules/modules.load; do
  [ -f "$f" ] && printf '  %-62s md5=%s 条目=%s\n' "$f" "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")" || echo "  缺 $f"
done
echo
echo "=== 版本化目录的 modules.load ==="
find /root/work/pixelos/mnt/system_dlkm/lib/modules /root/work/gstack/mnt/los_system_dlkm/lib/modules \
     -maxdepth 2 -name 'modules.load' 2>/dev/null | while read -r f; do
  printf '  %-70s md5=%s 条目=%s\n' "$f" "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")"
done
