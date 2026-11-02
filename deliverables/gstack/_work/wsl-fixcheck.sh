#!/bin/bash
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
O=/tmp/mnt
rm -rf $O && mkdir -p $O/{los_vd,stock_vd,los_sd,stock_sd}
mount -o loop,ro "$IMGS/vendor_dlkm.img" $O/los_vd
mount -t erofs -o loop,ro /tmp/stock_vendor_dlkm.img $O/stock_vd
mount -o loop,ro "$IMGS/system_dlkm.img" $O/los_sd
mount -t erofs -o loop,ro /tmp/stock_system_dlkm.img $O/stock_sd

echo "########## vendor_dlkm：LOS 加载清单 vs stock 模块集合 ##########"
L=$O/los_vd/lib/modules
S=$O/stock_vd/lib/modules
echo "LOS  .ko 文件数: $(ls $L/*.ko 2>/dev/null | wc -l)"
echo "LOS  modules.load 行数: $(grep -c . $L/modules.load)"
echo "stock .ko 文件数: $(ls $S/*.ko 2>/dev/null | wc -l)"
echo
echo "-- LOS 加载清单里，stock 侧有同名文件的比例 --"
tot=0; hit=0; miss=""
while read -r m; do
  [ -z "$m" ] && continue
  case "$m" in \#*) continue;; esac
  tot=$((tot+1))
  if [ -f "$S/$m" ]; then hit=$((hit+1)); else miss="$miss $m"; fi
done < <(awk '{print $1}' $L/modules.load)
echo "  清单条目(去重前): $tot ; stock 有同名: $hit ; 缺: $((tot-hit))"
echo "  缺失示例:$(echo $miss | tr ' ' '\n' | head -8 | tr '\n' ' ')"

echo
echo "########## vendor_dlkm：LOS 自身 .ko 的 CRC 分布 ##########"
ls $L/*.ko | xargs -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | grep -w module_layout' | awk '{print $1}' | sort | uniq -c | sort -rn

echo
echo "########## system_dlkm：两份副本各自的 CRC 分布（LOS） ##########"
for d in "$O/los_sd/flatten/lib/modules" "$O/los_sd/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k"; do
  echo "-- $d --"
  find "$d" -name '*.ko' -print0 | xargs -0 -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | grep -w module_layout' | awk '{print $1}' | sort | uniq -c | sort -rn
done

for m in los_vd stock_vd los_sd stock_sd; do umount $O/$m 2>/dev/null; done
