#!/bin/bash
# 确认 stock 的 vendor_dlkm modules.load 与 PixelOS 是否同一份
set -u
GS=/root/work/gstack
PX=/root/work/pixelos
mkdir -p "$GS/mnt/stock_vendor_dlkm" "$PX/mnt/vendor_dlkm"
mountpoint -q "$GS/mnt/stock_vendor_dlkm" || mount -t erofs -o loop,ro "$GS/stock_vendor_dlkm.img" "$GS/mnt/stock_vendor_dlkm" 2>/dev/null
mountpoint -q "$PX/mnt/vendor_dlkm" || mount -o loop,ro "$PX/vendor_dlkm.img" "$PX/mnt/vendor_dlkm" 2>/dev/null
S="$GS/mnt/stock_vendor_dlkm/lib/modules/modules.load"
P="$PX/mnt/vendor_dlkm/lib/modules/modules.load"
for f in "$S" "$P"; do
  [ -f "$f" ] || { echo "缺 $f"; exit 9; }
  printf '  md5=%s 条目=%-4s %s\n' "$(md5sum "$f" | cut -c1-12)" "$(grep -c . "$f")" "$f"
done
cmp -s "$S" "$P" && echo "  => 逐字节相同" || echo "  => 不同"
echo
echo "=== 顺带：stock 的 modules.alias/dep 与 PixelOS 是否相同 ==="
for n in modules.alias modules.dep modules.softdep modules.blocklist; do
  a=$(md5sum "$GS/mnt/stock_vendor_dlkm/lib/modules/$n" 2>/dev/null | cut -c1-12)
  b=$(md5sum "$PX/mnt/vendor_dlkm/lib/modules/$n" 2>/dev/null | cut -c1-12)
  printf '  %-18s stock=%s pixelos=%s %s\n' "$n" "$a" "$b" "$([ "$a" = "$b" ] && echo 相同 || echo 不同)"
done
