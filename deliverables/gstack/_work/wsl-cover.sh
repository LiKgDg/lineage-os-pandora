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

echo "########## 逐个核对：LOS 的错配模块，stock 是否有同名可替换件 ##########"
bad=0; cov=0; nocov=""
for f in $L/*.ko; do
  b=$(basename "$f")
  c=$(modprobe --dump-modversions "$f" 2>/dev/null | awk '$2=="module_layout"{print $1}')
  [ "$c" = "0x797f2b3e" ] && continue
  bad=$((bad+1))
  if [ -f "$S/$b" ]; then
    sc=$(modprobe --dump-modversions "$S/$b" 2>/dev/null | awk '$2=="module_layout"{print $1}')
    if [ "$sc" = "0x797f2b3e" ]; then cov=$((cov+1)); else nocov="$nocov $b(CRC不符)"; fi
  else
    nocov="$nocov $b(无同名)"
  fi
done
echo "LOS vendor_dlkm 错配模块: $bad"
echo "stock 有同名且 CRC 正确的替换件: $cov"
echo "无法直接替换: $((bad-cov))"
echo "  明细:$(echo $nocov | tr ' ' '\n' | head -12 | tr '\n' ' ')"

umount $O/los_vd $O/stock_vd 2>/dev/null
