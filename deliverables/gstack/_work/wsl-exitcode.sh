#!/bin/bash
# 退出码回归：用脚本文件测量，避免 bash -c 里 $? 被外层提前展开
set -u
V="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/verify_kernel_modules.sh"
G="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/kmi-gate.sh"
LOS=/root/work/gstack/fakeout/los/target/product/pandora
STK=/root/work/gstack/fakeout/stock/target/product/pandora

run() {  # $1=描述 $2=期望 $3..=命令
  local desc="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1
  local rc=$?
  if [ "$rc" = "$want" ]; then printf "  OK   %-40s exit=%s\n" "$desc" "$rc"
  else printf "  BAD  %-40s exit=%s 期望 %s\n" "$desc" "$rc" "$want"; fi
}

echo "=== 构建树模式 ==="
run "LOS 树（应失败）"   1 bash "$V" --out "$LOS" -q
run "stock 树（应通过）" 0 bash "$V" --out "$STK" -q

echo "=== 镜像模式 ==="
run "stock 镜像集（应通过）" 0 bash "$V" --images /root/work/gstack/imgset-stock
run "错误命名目录（应报错）" 2 bash "$V" --images /root/work/gstack
run "LOS 镜像集（应失败）"   1 bash "$V" --images "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"

echo "=== 门禁直跑 ==="
run "LOS vendor_ramdisk（应失败）" 1 bash "$G" -R -q "$LOS/vendor_ramdisk/lib/modules"
run "stock vendor_ramdisk（应通过）" 0 bash "$G" -R -q "$STK/vendor_ramdisk/lib/modules"
