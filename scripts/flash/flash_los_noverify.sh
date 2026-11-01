#!/bin/bash
# 测试：LOS 全量 + 两个 vbmeta 都关闭校验
FB="./platform-tools/fastboot.exe"
IMG="D:/WSL/out/pandora/los1101"

echo "=== 当前模式 ==="
$FB getvar is-userspace 2>&1 | head -1

ALL="boot init_boot dtbo vendor_boot system system_ext product vendor odm vendor_dlkm system_dlkm"
N=0; FAIL=0
TOTAL=$(echo $ALL | wc -w)

for p in $ALL; do
    N=$((N+1))
    f="$IMG/$p.img"
    [ -f "$f" ] || { echo "[$N] $p 缺失"; FAIL=1; break; }
    printf "[%2d/%d] %-14s " "$N" "$TOTAL" "$p"
    if out=$($FB flash "$p" "$f" 2>&1); then echo "OK"; else
        echo "FAILED"; echo "$out" | tail -4 | sed 's/^/      /'; FAIL=1; break
    fi
done

if [ "$FAIL" -eq 0 ]; then
    echo
    echo "=== 关闭校验刷 vbmeta / vbmeta_system ==="
    $FB --disable-verity --disable-verification flash vbmeta_system "$IMG/vbmeta_system.img" 2>&1 | tail -2
    $FB --disable-verity --disable-verification flash vbmeta "$IMG/vbmeta.img" 2>&1 | tail -2
fi

echo
[ "$FAIL" -eq 0 ] && echo "刷入完成（校验已关闭）" || echo "中断于第 $N 个"
