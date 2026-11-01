#!/bin/bash
# 恢复 pandora 原厂 A17 物理分区
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/stock-a17"
# vbmeta 放最后：前面失败时旧 vbmeta 仍能校验旧镜像
PARTS="boot init_boot dtbo vendor_boot vbmeta_system vbmeta"

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
    echo "原厂物理分区恢复完成（$TOTAL 个）"
else
    echo "中断于第 $N 个"
fi
