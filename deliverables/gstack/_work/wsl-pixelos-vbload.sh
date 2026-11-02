#!/bin/bash
# vendor_boot 的 modules.load 三方对账：LOS / stock / PixelOS
set -u
L=/root/work/gstack/vb/los/lib/modules/modules.load
S=/root/work/gstack/vb/stock/lib/modules/modules.load
P=/root/work/pixelos/vb/lib/modules/modules.load
for f in "$L" "$S" "$P"; do
  [ -f "$f" ] || { echo "FATAL: 缺 $f"; exit 9; }
  printf '%-48s md5=%s 条目=%s 唯一=%s\n' "$(basename "$(dirname "$(dirname "$f")")")" \
    "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")" "$(sort -u "$f" | grep -c .)"
done
echo
echo "=== stock 与 PixelOS 的清单是否逐字节相同 ==="
cmp -s "$S" "$P" && echo "  相同" || echo "  不同"

echo
echo "=== LOS 独有（文件是否存在） ==="
comm -23 <(sort -u "$L") <(sort -u "$S") | while read -r m; do
  printf "  %-24s 文件=%s\n" "$m" "$([ -f "/root/work/gstack/vb/los/lib/modules/$m" ] && echo 有 || echo 无)"
done

echo
echo "=== stock 独有（LOS 缺的 30 条，按平台归类） ==="
comm -13 <(sort -u "$L") <(sort -u "$S") | sed 's/^/  /'
