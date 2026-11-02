#!/bin/bash
# backup_los_tree.sh —— 把已同步的 LOS 设备/厂商树备份到 backup/
set -e
BK="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/backup/los-pandora"
mkdir -p "$BK"
echo "=== 备份设备树 ==="
cp -a /root/android/lineage/device/xiaomi/pandora "$BK/device-pandora"
du -sh "$BK/device-pandora"
echo "=== 备份 blob 包元数据（不含 5.9G 的 blob 实体）==="
mkdir -p "$BK/vendor-pandora"
for f in proprietary-files.txt Android.bp blob-stats.txt pandora-vendor.mk BoardConfigVendor.mk; do
  [ -f "/root/android/lineage/vendor/xiaomi/pandora/$f" ] && cp -a "/root/android/lineage/vendor/xiaomi/pandora/$f" "$BK/vendor-pandora/"
done
ls -la "$BK/vendor-pandora"
echo "=== 备份体积 ==="
du -sh "$BK"
