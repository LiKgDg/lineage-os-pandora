#!/bin/bash
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
O=/tmp/mnt

for n in vendor_dlkm system_dlkm; do
  echo "########## $n ##########"
  file /tmp/stock_$n.img | sed 's/.*: //'
  rm -rf $O/stock_$n; mkdir -p $O/stock_$n
  t=$(file -b /tmp/stock_$n.img)
  if echo "$t" | grep -qi erofs; then
    mount -t erofs -o loop,ro /tmp/stock_$n.img $O/stock_$n 2>&1 || echo "MOUNT FAIL"
  else
    mount -o loop,ro /tmp/stock_$n.img $O/stock_$n 2>&1 || echo "MOUNT FAIL"
  fi
  if mountpoint -q $O/stock_$n; then
    echo "-- 目录结构 --"; find $O/stock_$n -name 'modules.load' -o -name '*.ko' | head -3
    echo "-- ko 总数 --"; find $O/stock_$n -name '*.ko' | wc -l
    echo "-- modules.load --"; find $O/stock_$n -name 'modules.load' -exec sh -c 'echo "  $1 : $(wc -l < $1) 行"' _ {} \;
    echo "-- CRC 分布 --"
    find $O/stock_$n -name '*.ko' -print0 | xargs -0 -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | grep -w module_layout' | awk '{print $1}' | sort | uniq -c | sort -rn
    umount $O/stock_$n
  fi
  echo
done

echo "########## LOS 侧对照 ##########"
for n in vendor_dlkm system_dlkm; do
  echo "-- LOS $n --"
  file "$IMGS/$n.img" | sed 's/.*: //'
  rm -rf $O/los_$n; mkdir -p $O/los_$n
  mount -o loop,ro "$IMGS/$n.img" $O/los_$n 2>&1 | head -2
  if mountpoint -q $O/los_$n; then
    find $O/los_$n -name 'modules.load' -exec sh -c 'echo "  $1 : $(wc -l < $1) 行"' _ {} \;
    umount $O/los_$n
  fi
done
