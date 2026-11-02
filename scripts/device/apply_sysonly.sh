#!/bin/bash
# apply_sysonly.sh —— 同上，作用于 sysonly 变体的 device 树
set -e
S="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/staging"
D=/root/android/lineage/device/xiaomi/pandora
cp "$S/lineage_pandora_sysonly.mk" "$D/lineage_pandora_sysonly.mk"
cp "$S/AndroidProducts.mk" "$D/AndroidProducts.mk"
python3 "$S/patch_sysonly.py"
echo "--- AndroidProducts.mk ---"
cat "$D/AndroidProducts.mk"
echo "--- BoardConfig tail ---"
tail -14 "$D/BoardConfig.mk"
echo "--- device.mk 中是否还有 vendor blob 继承 ---"
grep -n "pandora-vendor.mk" "$D/device.mk" || echo "(已移除)"
