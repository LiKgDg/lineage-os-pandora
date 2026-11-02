#!/bin/bash
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
WORK="$W/deliverables/gstack/_work"
IMG="$WORK/stock_vendor.img"
MNT=/mnt/erofs_vendor

mkdir -p "$MNT"
echo "===== try loop mount (erofs) ====="
sudo -n mount -t erofs -o loop,ro "$IMG" "$MNT" 2>&1 && echo "MOUNT OK" || echo "MOUNT FAILED"

if mountpoint -q "$MNT"; then
  echo "===== /etc/fstab.qcom (stock, EROFS mount) ====="
  ls -l "$MNT/etc/fstab.qcom"
  sha256sum "$MNT/etc/fstab.qcom"
  cat "$MNT/etc/fstab.qcom"
  sudo -n umount "$MNT"
  exit 0
fi

echo "===== fallback: fsck.erofs --extract ====="
rm -rf /tmp/vout && mkdir -p /tmp/vout
time fsck.erofs --extract=/tmp/vout "$IMG" 2>&1 | tail -5
echo "===== extracted file ====="
ls -l /tmp/vout/etc/fstab.qcom 2>&1
sha256sum /tmp/vout/etc/fstab.qcom 2>&1
cat /tmp/vout/etc/fstab.qcom 2>&1
