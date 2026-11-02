#!/bin/bash
# flash_kernel_a17.sh —— 逐分区刷 A17 内核相关的 5 个分区（boot dtbo vendor_boot vendor_dlkm system_dlkm）
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/kernel-a17"
PARTS="boot dtbo vendor_boot vendor_dlkm system_dlkm"
FAIL=0; N=0
TOTAL=$(echo $PARTS | wc -w)
START=$(date +%s)

for p in $PARTS; do
    N=$((N+1))
    f="$IMG/$p.img"
    [ -f "$f" ] || { echo "[$N/$TOTAL] $p 镜像缺失"; FAIL=1; break; }
    sz=$(stat -c %s "$f")
    echo "[$N/$TOTAL] $p ($((sz/1048576)) MB)"
    if out=$($FB flash "$p" "$f" 2>&1); then
        echo "         OK"
    else
        echo "         FAILED"
        echo "$out" | tail -5 | sed 's/^/         /'
        FAIL=1
        break
    fi
done

END=$(date +%s)
echo
echo "=========================================="
[ "$FAIL" -eq 0 ] && echo "全部 $TOTAL 个分区刷入成功，耗时 $((END-START)) 秒" \
                  || echo "中断于第 $N 个，耗时 $((END-START)) 秒"
echo "=========================================="

# 失败必须体现在退出码上：调用方/CI 靠 $? 判断，不能只靠屏幕上的「中断于第 N 个」
exit "$FAIL"
