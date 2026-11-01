#!/bin/bash
# fastbootd 模式一次性刷入 LOS 全部 13 个分区
# vbmeta 放最后：前面任何一步失败时旧 vbmeta 仍能校验旧镜像
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/los1101"

PHYS="boot init_boot dtbo vendor_boot"
LOGICAL="system system_ext product vendor odm vendor_dlkm system_dlkm"
TAIL="vbmeta_system vbmeta"

ALL="$PHYS $LOGICAL $TAIL"
TOTAL=$(echo $ALL | wc -w)
N=0; FAIL=0
START=$(date +%s)

for p in $ALL; do
    N=$((N+1))
    f="$IMG/$p.img"
    [ -f "$f" ] || { echo "[$N/$TOTAL] $p 镜像缺失"; FAIL=1; break; }
    sz=$(stat -c %s "$f")
    printf "[%2d/%d] %-14s %5s MB  " "$N" "$TOTAL" "$p" "$((sz/1048576))"
    t0=$(date +%s)
    if out=$($FB flash "$p" "$f" 2>&1); then
        echo "OK  $(( $(date +%s)-t0 ))s"
    else
        echo "FAILED"
        echo "$out" | tail -5 | sed 's/^/       /'
        FAIL=1; break
    fi
done

END=$(date +%s)
echo
echo "=========================================="
if [ "$FAIL" -eq 0 ]; then
    echo "全部 $TOTAL 个分区刷入成功，耗时 $((END-START)) 秒"
else
    echo "中断于第 $N 个（已完成 $((N-1))/$TOTAL），耗时 $((END-START)) 秒"
fi
echo "=========================================="
