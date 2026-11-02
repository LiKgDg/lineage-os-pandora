#!/bin/bash
# 验证「镜像内旧 KMI 字符串计数」能否作为刷机前的干净判据
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
STAGE=/root/work/gstack

printf "%-26s %-10s %-10s\n" 镜像 "旧世代计数" "新世代计数"
for pair in "LOS:vendor_boot:$IMGS/vendor_boot.img" \
            "LOS:vendor_dlkm:$IMGS/vendor_dlkm.img" \
            "LOS:system_dlkm:$IMGS/system_dlkm.img" \
            "stock:vendor_boot:$STAGE/stock_vendor_boot.img" \
            "stock:vendor_dlkm:$STAGE/stock_vendor_dlkm.img" \
            "stock:system_dlkm:$STAGE/stock_system_dlkm.img"; do
  tag=${pair%%:*}; rest=${pair#*:}; name=${rest%%:*}; f=${rest#*:}
  [ -f "$f" ] || { printf "%-26s 缺失\n" "$tag/$name"; continue; }
  a16=$(strings -a "$f" | grep -c "6\.12\.23-android16-5")
  a17=$(strings -a "$f" | grep -c "6\.12\.69-android16-6")
  printf "%-26s %-10s %-10s\n" "$tag/$name" "$a16" "$a17"
done
