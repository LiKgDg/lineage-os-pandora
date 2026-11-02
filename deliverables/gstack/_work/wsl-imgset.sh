#!/bin/bash
# 构造「命名正确的 stock 镜像目录」，验证镜像模式能真正判 PASS（而不是空集合假通过）
set -u
S=/root/work/gstack
D=$S/imgset-stock
rm -rf "$D"; mkdir -p "$D"
for n in vendor_boot vendor_dlkm system_dlkm; do
  [ -f "$S/stock_$n.img" ] && cp "$S/stock_$n.img" "$D/$n.img"
done
ls -l "$D"
echo "--- 跑镜像模式（期望 PASS, exit 0）---"
bash "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/verify_kernel_modules.sh" --images "$D"
echo "exit=$?"
