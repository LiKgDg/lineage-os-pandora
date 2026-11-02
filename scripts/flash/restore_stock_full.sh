#!/bin/bash
# 完整恢复 pandora 原厂 A17：物理分区 + super（逻辑分区）
FB="./platform-tools/fastboot.exe"
P="D:/WSL/out/pandora/stock-a17"
S="D:/WSL/out/pandora/stock-super/super.img"

PARTS="boot init_boot dtbo vendor_boot recovery vbmeta_system vbmeta"
N=0; FAIL=0
TOTAL=8
START=$(date +%s)

for p in $PARTS; do
    N=$((N+1))
    f="$P/$p.img"
    [ -f "$f" ] || { echo "[$N/$TOTAL] $p 缺失"; FAIL=1; break; }
    printf "[%d/%d] %-14s " "$N" "$TOTAL" "$p"
    if out=$($FB flash "$p" "$f" 2>&1); then echo "OK"; else
        echo "FAILED"; echo "$out" | tail -4 | sed 's/^/      /'; FAIL=1; break
    fi
done

if [ "$FAIL" -eq 0 ]; then
    N=$((N+1))
    printf "[%d/%d] %-14s " "$N" "$TOTAL" "super"
    if out=$($FB flash super "$S" 2>&1); then
        echo "OK"
    else
        echo "FAILED"; echo "$out" | tail -6 | sed 's/^/      /'; FAIL=1
    fi
fi

END=$(date +%s)
echo
echo "=========================================="
[ "$FAIL" -eq 0 ] && echo "原厂完整恢复成功，耗时 $((END-START)) 秒" \
                  || echo "恢复中断于第 $N 个，耗时 $((END-START)) 秒"
echo "=========================================="

# 失败必须体现在退出码上：调用方/CI 靠 $? 判断，不能只靠屏幕上的「中断于第 N 个」
exit "$FAIL"
