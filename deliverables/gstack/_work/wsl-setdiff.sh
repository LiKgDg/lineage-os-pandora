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

ls $L/*.ko | xargs -n1 basename | sort > /tmp/l.txt
ls $S/*.ko | xargs -n1 basename | sort > /tmp/s.txt
echo "########## vendor_dlkm 模块名集合差异 ##########"
echo "LOS: $(wc -l < /tmp/l.txt)   stock: $(wc -l < /tmp/s.txt)"
echo "共有: $(comm -12 /tmp/l.txt /tmp/s.txt | wc -l)"
echo "仅 LOS 有: $(comm -23 /tmp/l.txt /tmp/s.txt | wc -l)"
comm -23 /tmp/l.txt /tmp/s.txt | sed 's/^/    LOS-only: /' | head -20
echo "仅 stock 有: $(comm -13 /tmp/l.txt /tmp/s.txt | wc -l)"
comm -13 /tmp/l.txt /tmp/s.txt | sed 's/^/    STOCK-only: /' | head -20

echo
echo "########## 两侧共有模块里，内容完全相同的比例 ##########"
same=0; diff=0
while read -r m; do
  if cmp -s "$L/$m" "$S/$m"; then same=$((same+1)); else diff=$((diff+1)); fi
done < <(comm -12 /tmp/l.txt /tmp/s.txt)
echo "  共有模块: 内容相同 $same / 不同 $diff"

echo
echo "########## LOS modules.load 是否引用了 stock 没有的模块 ##########"
awk '{print $1}' $L/modules.load | grep -v '^#' | grep -v '^$' | sort -u > /tmp/ll.txt
echo "  LOS 清单去重: $(wc -l < /tmp/ll.txt) 条"
echo "  其中 stock 侧无同名文件: $(comm -23 /tmp/ll.txt /tmp/s.txt | wc -l)"
comm -23 /tmp/ll.txt /tmp/s.txt | sed 's/^/    /'

umount $O/los_vd $O/stock_vd 2>/dev/null
