#!/bin/bash
# apply.sh —— 把 staging/ 下的配置改动同步进 device/xiaomi/pandora
set -e
S="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/staging"
D=/root/android/lineage/device/xiaomi/pandora
cp "$S/lineage_pandora.mk" "$D/lineage_pandora.mk"
mkdir -p "$D/vintf"
cat "$S/boardconfig-append.mk" >> "$D/BoardConfig.mk"
cat "$S/device-append.mk" >> "$D/device.mk"
echo "--- lineage_pandora.mk ---"
head -8 "$D/lineage_pandora.mk"
echo "--- tail BoardConfig.mk ---"
tail -6 "$D/BoardConfig.mk"
echo "--- tail device.mk ---"
tail -6 "$D/device.mk"
