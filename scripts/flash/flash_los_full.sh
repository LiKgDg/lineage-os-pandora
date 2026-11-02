#!/bin/bash
# fastbootd 模式一次性刷入 LOS 全部 13 个分区
# vbmeta 放最后：前面任何一步失败时旧 vbmeta 仍能校验旧镜像
#
# 刷之前会先跑一遍镜像级 KMI 检查（scripts/maintain/verify_kernel_modules.sh
# --images）。内核换了、模块没换的构建在这里就被拦住，不用拿刷机次数去换。
#
# 用法：
#   ./flash_los_full.sh                        # 用 LOS_IMG 或默认目录
#   ./flash_los_full.sh --img /path/to/images
#   ./flash_los_full.sh --no-check             # 跳过 KMI 检查（只在明确知道原因时用）
#   ./flash_los_full.sh --yes                  # 不询问
#
# 退出码：0 全部成功 / 1 有分区失败 / 2 前置检查未过
set -u

FB="./platform-tools/fastboot.exe"
IMG="${LOS_IMG:-D:/WSL/out/pandora/modfix}"
DO_CHECK=1
ASSUME_YES=0

while [ $# -gt 0 ]; do
    case "$1" in
        --img)      [ $# -ge 2 ] || { echo "flash_los_full.sh: --img 需要参数" >&2; exit 2; }
                    IMG="$2"; shift 2 ;;
        --img=*)    IMG="${1#*=}"; shift ;;
        --no-check) DO_CHECK=0; shift ;;
        -y|--yes)   ASSUME_YES=1; shift ;;
        -h|--help)  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          echo "flash_los_full.sh: 未知参数 $1" >&2; exit 2 ;;
    esac
done

PHYS="boot init_boot dtbo vendor_boot"
LOGICAL="system system_ext product vendor odm vendor_dlkm system_dlkm"
TAIL="vbmeta_system vbmeta"

ALL="$PHYS $LOGICAL $TAIL"
TOTAL=$(echo $ALL | wc -w)

# 主机侧留痕：命令一律 tee 到 docs/logs/<UTC>-<动作>.log，事后可复核
LOG="docs/logs/$(date -u +%Y%m%dT%H%M%SZ)-flash-los-full.log"
mkdir -p docs/logs
exec > >(tee -a "$LOG") 2>&1
echo "日志: $LOG"

echo "=== 前置检查 ==="
[ -d "$IMG" ] || { echo "镜像目录不存在: $IMG"; exit 2; }
[ -x "$FB" ]  || { echo "找不到 $FB"; exit 2; }

# 1) 镜像级 KMI 检查：拦「内核换了、模块没换」
if [ "$DO_CHECK" -eq 1 ]; then
    if ! bash scripts/maintain/verify_kernel_modules.sh --images "$IMG"; then
        echo
        echo "KMI 检查未通过 —— 拒绝刷机。确认要刷请加 --no-check，但先想清楚为什么。"
        exit 2
    fi
else
    echo "  （--no-check：跳过 KMI 检查）"
fi

# 2) 设备必须已在 fastbootd，否则逻辑分区刷不进去
STATE=$($FB getvar is-userspace 2>&1 | grep -oE 'yes|no' | head -1)
if [ "$STATE" != "yes" ]; then
    echo "  设备不在 fastbootd（is-userspace=${STATE:-取不到}）—— 先跑 fastboot reboot fastboot"
    exit 2
fi
echo "  fastbootd 就绪"

if [ "$ASSUME_YES" -eq 0 ]; then
    echo
    echo "即将刷入 $TOTAL 个分区，来源 $IMG"
    printf "继续？输入 YES："
    read -r ans
    [ "$ans" = "YES" ] || { echo "已取消"; exit 2; }
fi

echo
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

# 失败必须体现在退出码上：调用方/CI 靠 $? 判断，不能只靠屏幕上的「中断于第 N 个」
exit "$FAIL"
