#!/bin/bash
# apply_rcmode_patch.sh —— 把 rc-mode 二进制装进 recovery/root/system/bin
set -e
S="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/staging"
D=/root/android/lineage/device/xiaomi/pandora/recovery/root

install -m 0755 "$S/rc-mode" "$D/system/bin/rc-mode"
echo "=== rc-mode ==="
ls -la "$D/system/bin/rc-mode"

echo "=== USB 重新枚举补丁 ==="
python3 "$S/patch_usb_reenum.py"

echo "=== 切换时序补丁 ==="
python3 "$S/patch_usb_ordering.py"

echo "=== 校验 qcom.rc 末尾 ==="
tail -18 "$D/init.recovery.qcom.rc"
