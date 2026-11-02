#!/bin/bash
# 来源校验：设备抽样哈希 vs PixelOS 镜像内同名文件
set -u
PX=/root/work/pixelos
DEV="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work/device-pixelos"

for p in vendor_dlkm system_dlkm; do
  mnt="$PX/mnt/$p"; mkdir -p "$mnt"
  mountpoint -q "$mnt" || mount -o loop,ro "$PX/$p.img" "$mnt" 2>/dev/null
  [ -d "$mnt/lib" ] || { echo "FATAL: 挂载 $p 失败"; exit 9; }
done

check() {   # check <样本文件> <镜像根目录>
  local samp="$1" root="$2" hit=0 miss=0 diff=0
  while read -r h path; do
    [ -z "${h:-}" ] && continue
    local name; name=$(basename "$path")
    local img; img=$(find "$root" -name "$name" -type f 2>/dev/null | head -1)
    if [ -z "$img" ]; then
      miss=$((miss+1)); echo "    镜像缺: $name"
      continue
    fi
    local ih; ih=$(md5sum "$img" | awk '{print $1}')
    if [ "$ih" = "$h" ]; then hit=$((hit+1)); else diff=$((diff+1)); echo "    不一致: $name  设备=$h 镜像=$ih"; fi
  done < "$samp"
  echo "    相同 $hit / 不一致 $diff / 镜像缺失 $miss"
}

echo "=== vendor_dlkm 抽样（20 个）==="
check "$DEV/out3/vd-sample.txt" "$PX/mnt/vendor_dlkm/lib/modules"

echo "=== system_dlkm 版本化抽样（10 个）==="
check "$DEV/out3/sd-sample.txt" "$PX/mnt/system_dlkm/lib/modules"

echo "=== system_dlkm flatten 抽样（10 个）==="
check "$DEV/out3/sdflat-sample.txt" "$PX/mnt/system_dlkm/flatten"
