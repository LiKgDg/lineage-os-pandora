#!/bin/bash
# system-only 刷机：super.img 路线（设备需在 bootloader fastboot 模式）
set -e
cd "/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
FB="F:/BaiduNetdiskDownload/2/1/Xiaomi 17 Pro 3.0.318[A2083]/bin/windows/fastboot.exe"

echo "=== 0. 确认设备 ==="
"$FB" devices
"$FB" getvar current-slot 2>&1 | head -1

echo "=== 1. 刷 super（8 个逻辑分区：LOS 的 system/system_ext/product + stock 其余 5 个）==="
"$FB" flash super sysonly/super.img

echo "=== 2. 关闭 AVB 校验（system 内容已变，原 vbmeta 哈希必然不匹配）==="
"$FB" --disable-verity --disable-verification flash vbmeta vbmeta-stock.img

echo "=== 3. 重启 ==="
"$FB" reboot
