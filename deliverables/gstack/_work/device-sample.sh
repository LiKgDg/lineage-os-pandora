#!/system/bin/sh
# 抽样 30 个模块做 md5，用于与镜像比对来源
set -u
OUT="${1:-/data/local/tmp/out3}"
mkdir -p "$OUT"

VD=/vendor_dlkm/lib/modules
SD=/system_dlkm/lib/modules

# vendor_dlkm：按字母序均匀取 20 个
ls "$VD"/*.ko | awk 'NR%20==1' | head -20 | while read -r f; do
  md5sum "$f"
done > "$OUT/vd-sample.txt" 2>&1

# system_dlkm 版本化：取 10 个
find "$SD" -name '*.ko' | sort | awk 'NR%10==1' | head -10 | while read -r f; do
  md5sum "$f"
done > "$OUT/sd-sample.txt" 2>&1

# flatten 副本：取 10 个
find /system_dlkm/flatten -name '*.ko' | sort | awk 'NR%10==1' | head -10 | while read -r f; do
  md5sum "$f"
done > "$OUT/sdflat-sample.txt" 2>&1

echo "vd=$(grep -c . "$OUT/vd-sample.txt") sd=$(grep -c . "$OUT/sd-sample.txt") flat=$(grep -c . "$OUT/sdflat-sample.txt")"
