#!/bin/bash
# system-only 刷机流程（设备需先在 bootloader fastboot 模式）
set -e
cd "/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
FB="F:/BaiduNetdiskDownload/2/1/Xiaomi 17 Pro 3.0.318[A2083]/bin/windows/fastboot.exe"
ADB="./platform-tools/adb.exe"

echo "=== 1. 刷 recovery_a ==="
"$FB" flash recovery_a sysonly/recovery.img
"$FB" reboot recovery

echo "=== 2. 等 recovery adb ==="
for i in $(seq 1 20); do
  sleep 3
  st=$($ADB devices | grep fd3af370 | awk '{print $2}')
  if [ "$st" = "recovery" ]; then echo "adb recovery up (${i}x3s)"; break; fi
  echo "  state=$st"
done

echo "=== 3. 进入 fastbootd ==="
$ADB reboot fastboot || true
for i in $(seq 1 20); do
  sleep 3
  if "$FB" devices | grep -q fastboot; then echo "fastbootd up (${i}x3s)"; break; fi
done
"$FB" devices

echo "=== 4. 刷 system / system_ext / product ==="
"$FB" flash system      sysonly/system.img
"$FB" flash system_ext  sysonly/system_ext.img
"$FB" flash product     sysonly/product.img

echo "=== 5. 关闭验证并重启 ==="
"$FB" --disable-verity --disable-verification flash vbmeta vbmeta.img || echo "(vbmeta 跳过)"
"$FB" reboot
