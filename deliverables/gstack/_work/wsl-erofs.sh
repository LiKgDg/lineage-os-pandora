#!/bin/bash
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
WORK="$W/deliverables/gstack/_work"

echo "===== dump.erofs version ====="
dump.erofs --version 2>&1 | head -3
echo "===== fsck.erofs version ====="
fsck.erofs --version 2>&1 | head -3

echo
echo "===== stock vendor.img format ====="
file "$WORK/stock_vendor.img"

echo
echo "===== try dump.erofs --cat /etc/fstab.qcom ====="
dump.erofs --cat="/etc/fstab.qcom" "$WORK/stock_vendor.img" 2>&1 | head -80
