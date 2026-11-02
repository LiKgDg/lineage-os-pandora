#!/bin/bash
# 补齐 LOS 物理分区（含 recovery），凑齐完整 AVB 签名集
FB="./platform-tools/fastboot.exe"
IMG="${LOS_IMG:-D:/WSL/out/pandora/los1101}"
PARTS="recovery boot init_boot dtbo vendor_boot vbmeta_system vbmeta"

# 前置：镜像级 KMI 检查。本脚本会刷 vendor_boot，内核换了、模块没换的构建
# 在这里就该被拦住。设 LOS_SKIP_KMI_CHECK=1 可跳过。
if [ "${LOS_SKIP_KMI_CHECK:-0}" != "1" ]; then
    if ! bash scripts/maintain/verify_kernel_modules.sh --images "$IMG"; then
        echo
        echo "KMI 检查未通过 —— 拒绝刷机（要跳过请设 LOS_SKIP_KMI_CHECK=1）"
        exit 2
    fi
    echo
fi

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

# 失败必须体现在退出码上：调用方/CI 靠 $? 判断，不能只靠屏幕上的「中断于第 N 个」
exit "$FAIL"
