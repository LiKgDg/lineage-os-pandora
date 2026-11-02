#!/bin/bash
# 刷入 pandora LineageOS 镜像（fastbootd）
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/images"

# 顺序：先物理分区，vbmeta 放最后
PARTS="boot init_boot vendor_boot dtbo system_dlkm vendor_dlkm system system_ext product vendor odm vbmeta_system vbmeta"

TOTAL=$(echo $PARTS | wc -w)
FAIL=0
N=0
START=$(date +%s)

for p in $PARTS; do
    N=$((N+1))
    f="$IMG/$p.img"
    if [ ! -f "$f" ]; then
        echo "[$N/$TOTAL] $p  镜像缺失，中止"
        FAIL=1
        break
    fi
    sz=$(stat -c %s "$f")
    echo "[$N/$TOTAL] $p  ($((sz/1048576)) MB)"
    t0=$(date +%s)
    if out=$($FB flash "$p" "$f" 2>&1); then
        t1=$(date +%s)
        echo "         OK  $((t1-t0))s"
    else
        echo "         FAILED"
        echo "$out" | tail -6 | sed 's/^/         /'
        FAIL=1
        break
    fi
done

END=$(date +%s)
echo
echo "=========================================="
if [ "$FAIL" -eq 0 ]; then
    echo "全部 $TOTAL 个分区刷入成功，耗时 $((END-START)) 秒"
else
    echo "刷入中断（已完成 $((N-1))/$TOTAL），耗时 $((END-START)) 秒"
fi
echo "=========================================="

# 失败必须体现在退出码上：调用方/CI 靠 $? 判断，不能只靠屏幕上的「中断于第 N 个」
exit "$FAIL"
