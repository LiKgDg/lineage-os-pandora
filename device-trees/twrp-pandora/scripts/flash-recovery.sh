#!/bin/bash
# flash-recovery.sh —— 把编好的 recovery.img 刷进 pandora 并进入 recovery
#
# 必须在 **Windows** 上执行（WSL 没有 USB 透传，看不到设备）。
#   FASTBOOT=".../platform-tools/fastboot.exe" bash scripts/flash-recovery.sh
set -euo pipefail

FASTBOOT="${FASTBOOT:-fastboot}"
RECOVERY_IMG="${RECOVERY_IMG:-/root/android/lineage/out/target/product/pandora/recovery.img}"

[ -f "$RECOVERY_IMG" ] || { echo "错误：找不到 $RECOVERY_IMG" >&2; exit 2; }

echo "[1/4] 检查设备"
"$FASTBOOT" devices | grep -q fastboot || {
    echo "错误：fastboot 看不到设备。确认已进 bootloader、USB 已连接" >&2; exit 2; }

echo "[2/4] 当前槽位"
"$FASTBOOT" getvar current-slot 2>&1 | head -1

echo "[3/4] 刷入 recovery"
"$FASTBOOT" flash recovery "$RECOVERY_IMG"

echo "[4/4] 重启进 recovery"
"$FASTBOOT" reboot recovery

echo
echo "进入 recovery 后可验证："
echo "  adb devices            # 期望显示 <serial>  recovery"
echo "  adb reboot sideload    # 直接切 sideload"
