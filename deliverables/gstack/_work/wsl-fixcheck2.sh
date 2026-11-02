#!/bin/bash
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
WORK="$W/deliverables/gstack/_work"
O=/tmp/mnt

# 1) 持久化提取 stock 的 dlkm 分区（/tmp 会被 WSL 重启清掉）
if [ ! -f "$WORK/stock_vendor_dlkm.img" ] || [ ! -f "$WORK/stock_system_dlkm.img" ]; then
  echo "== 提取 stock dlkm 分区 =="
  sed -e "s#/tmp/stock_#${WORK}/stock_#" "$WORK/wsl_extract_part.py" > /tmp/ex.py
  python3 /tmp/ex.py vendor_dlkm system_dlkm
fi

rm -rf $O && mkdir -p $O/{los_vd,stock_vd,los_sd,stock_sd}
mount -o loop,ro "$IMGS/vendor_dlkm.img" $O/los_vd
mount -t erofs -o loop,ro "$WORK/stock_vendor_dlkm.img" $O/stock_vd
mount -o loop,ro "$IMGS/system_dlkm.img" $O/los_sd
mount -t erofs -o loop,ro "$WORK/stock_system_dlkm.img" $O/stock_sd

L=$O/los_vd/lib/modules
S=$O/stock_vd/lib/modules

echo
echo "########## vendor_dlkm 概览 ##########"
echo "LOS  .ko: $(ls $L/*.ko 2>/dev/null | wc -l)   modules.load: $(grep -c . $L/modules.load) 行"
echo "stock .ko: $(ls $S/*.ko 2>/dev/null | wc -l)  modules.load: $(grep -c . $S/modules.load) 行"

echo
echo "########## LOS 加载清单 vs stock 模块集合 ##########"
tot=0; hit=0
while read -r m; do
  [ -z "$m" ] && continue
  case "$m" in \#*) continue;; esac
  tot=$((tot+1))
  [ -f "$S/$m" ] && hit=$((hit+1))
done < <(awk '{print $1}' $L/modules.load)
echo "  条目 $tot ; stock 有同名 $hit ; 缺 $((tot-hit))"

echo
echo "########## CRC 分布（modprobe 实测） ##########"
echo "-- LOS vendor_dlkm --"
ls $L/*.ko | xargs -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | grep -w module_layout' | awk '{print $1}' | sort | uniq -c | sort -rn
echo "-- stock vendor_dlkm --"
ls $S/*.ko | xargs -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | grep -w module_layout' | awk '{print $1}' | sort | uniq -c | sort -rn

echo
echo "########## LOS system_dlkm 两份副本 ##########"
for d in "$O/los_sd/flatten/lib/modules" "$O/los_sd/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k"; do
  echo "-- ${d#$O/los_sd} --"
  find "$d" -name '*.ko' -print0 | xargs -0 -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | grep -w module_layout' | awk '{print $1}' | sort | uniq -c | sort -rn
done

echo
echo "########## LOS system_dlkm 实际加载清单指向哪份 ##########"
for f in "$O/los_sd/lib/modules/modules.load" "$O/los_sd/flatten/lib/modules/modules.load"; do
  [ -f "$f" ] && echo "$f : $(grep -c . $f) 行"
done
head -5 "$O/los_sd/lib/modules/6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k/modules.load"

for m in los_vd stock_vd los_sd stock_sd; do umount $O/$m 2>/dev/null; done
