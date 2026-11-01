#!/bin/bash
# 补齐 LOS 物理分区（含 recovery），凑齐完整 AVB 签名集
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/los1101"
PARTS="recovery boot init_boot dtbo vendor_boot vbmeta_system vbmeta"

N=0; FAIL=0
TOTAL=$(echo $PARTS | wc -w)
for p in $PARTS; do
    N=$((N+1))
    f="$IMG/$p.img"
    [ -f "$f" ] || { echo "[$N/$TOTAL] $p 缺失"; FAIL=1; break; }
    printf "[%d/%d] %-14s " "$N" "$TOTAL" "$p"
    if out=$($FB flash "$p" "$f" 2>&1); then
        echo "OK"
    else
        echo "FAILED"
        echo "$out" | tail -4 | sed 's/^/      /'
        FAIL=1; break
    fi
done

echo
[ "$FAIL" -eq 0 ] && echo "LOS 物理分区补齐完成（$TOTAL 个，含 recovery）" || echo "中断于第 $N 个"
