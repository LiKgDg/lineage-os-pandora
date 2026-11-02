#!/bin/bash
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
WORK="$W/deliverables/gstack/_work"
O=/tmp/mnt
rm -rf $O && mkdir -p $O/{los_vd,stock_vd}
mount -o loop,ro "$IMGS/vendor_dlkm.img" $O/los_vd
mount -t erofs -o loop,ro "$WORK/stock_vendor_dlkm.img" $O/stock_vd
L=$O/los_vd/lib/modules; S=$O/stock_vd/lib/modules

echo "########## LOS vendor_dlkm modules.load 质量 ##########"
awk '{print $1}' $L/modules.load | grep -v '^#' | grep -v '^$' > /tmp/ll.txt
echo "条目总数: $(wc -l < /tmp/ll.txt)  去重后: $(sort -u /tmp/ll.txt | wc -l)"
echo "重复条目示例:"
sort /tmp/ll.txt | uniq -d | head -5
echo
echo "########## 去重后，stock 缺哪些 ##########"
while read -r m; do [ -f "$S/$m" ] || echo "  MISSING: $m"; done < <(sort -u /tmp/ll.txt)
echo
echo "########## 这 8 个在 LOS vendor_boot ramdisk 里吗 ##########"
for m in $(while read -r x; do [ -f "$S/$x" ] || echo "$x"; done < <(sort -u /tmp/ll.txt)); do
  if [ -f "$O/../verify/los_vb/lib/modules/$m" ]; then echo "  $m -> 在 vendor_boot"; else echo "  $m -> vendor_boot 也没有"; fi
done

echo
echo "########## LOS vendor_dlkm 里未被 modules.load 引用的文件 ##########"
for f in $L/*.ko; do b=$(basename "$f"); grep -qx "$b" /tmp/ll.txt || echo "  UNREF: $b"; done | head -10

umount $O/los_vd $O/stock_vd 2>/dev/null
