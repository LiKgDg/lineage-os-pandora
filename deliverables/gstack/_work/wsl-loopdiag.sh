#!/bin/bash
# 诊断 loop 挂载失败
LOSIMG="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
echo "镜像存在: $([ -f "$LOSIMG/vendor_dlkm.img" ] && echo Y || echo N)"
ls -l /dev/loop-control /dev/loop0 2>&1 | head -3
echo "--- modprobe loop ---"
modprobe loop 2>&1; echo "rc=$?"
ls /dev/loop* 2>&1 | head -5
echo "--- 手动 losetup ---"
LOOP=$(losetup -f 2>&1); echo "空闲: $LOOP"
losetup -r "$LOOP" "$LOSIMG/vendor_dlkm.img" 2>&1; echo "losetup rc=$?"
mkdir -p /root/work/gstack/mnt/los_vendor_dlkm
mount -t ext4 -o ro "$LOOP" /root/work/gstack/mnt/los_vendor_dlkm 2>&1; echo "mount rc=$?"
ls /root/work/gstack/mnt/los_vendor_dlkm 2>&1 | head -3
