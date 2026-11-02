#!/bin/bash
# 阶段 1：bootloader 模式刷物理分区
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/los1101"
PARTS="boot init_boot dtbo vendor_boot vbmeta vbmeta_system"

FAIL=0; N=0
TOTAL=$(echo $PARTS | wc -w)
for p in $PARTS; do
    N=$((N+1))
    f="$IMG/$p.img"
    [ -f "$f" ] || { echo "[$N/$TOTAL] $p 缺失"; FAIL=1; break; }
    printf "[%d/%d] %-16s " "$N" "$TOTAL" "$p"
    if out=$($FB flash "$p" "$f" 2>&1); then
        echo "OK"
    else
        echo "FAILED"
        echo "$out" | tail -4 | sed 's/^/      /'
        FAIL=1; break
    fi
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "阶段 1 完成（$TOTAL 个物理分区）"
else
    echo "阶段 1 中断于第 $N 个"
fi

# 失败必须体现在退出码上：调用方/CI 靠 $? 判断，不能只靠屏幕上的「中断于第 N 个」
exit "$FAIL"
