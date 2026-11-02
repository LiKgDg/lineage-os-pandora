#!/bin/bash
# 清理 out/target/product/pandora 下混入旧世代模块的残留暂存
#
# 为什么需要：内核换成 6.12.69（android16-6）后，若 out/ 里还留着 6.12.23
# （android16-5）的 .ko，soong 会认为「文件已存在」而跳过拷贝，旧模块就这样
# 被带进 vendor_boot / vendor_dlkm / system_dlkm。见 INC-PANDORA-LOS24-001。
#
# 本脚本只负责「删干净」，判断是否干净请用 verify_kernel_modules.sh（判据是
# module_layout 的 CRC，比这里的 vermagic 字符串统计更准）。
#
# 用法：
#   ./clean_stale_modules.sh
#   ./clean_stale_modules.sh --out /path/to/out/target/product/pandora
#   ./clean_stale_modules.sh --dry-run      # 只报不删
set -u

PROG=$(basename "$0")
P=/root/los24/out/target/product/pandora
DRY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --out)     [ $# -ge 2 ] || { echo "$PROG: --out 需要参数" >&2; exit 2; }
                   P="$2"; shift 2 ;;
        --out=*)   P="${1#*=}"; shift ;;
        --dry-run) DRY=1; shift ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)         echo "$PROG: 未知参数 $1" >&2; exit 2 ;;
    esac
done

[ -d "$P" ] || { echo "$PROG: 构建产物目录不存在: $P" >&2; exit 2; }

A16_PAT="6\.12\.23-android16-5"
A17_PAT="6\.12\.69-android16-6"

# system_dlkm 下有两份：版本化目录（运行期主路径）与 flatten 副本。
# 漏掉 flatten 是本次事故的直接成因之一——它一直没人看。
MODDIRS=(
    "$P/vendor_ramdisk/lib/modules"
    "$P/vendor_dlkm/lib/modules"
    "$P/system_dlkm/flatten/lib/modules"
)
# 版本化目录名随内核变化，用 glob 兜住
for d in "$P"/system_dlkm/lib/modules/6.12.*/; do
    [ -d "$d" ] && MODDIRS+=("$d")
done

echo "=== 清理前：模块世代统计（$P）==="
for dir in "${MODDIRS[@]}"; do
    [ -d "$dir" ] || { printf "  %-52s 目录不存在\n" "${dir#$P/}"; continue; }
    n=$(find "$dir" -name "*.ko" 2>/dev/null | wc -l)
    a16=$(find "$dir" -name "*.ko" -exec sh -c \
        'strings -a "$1" 2>/dev/null | grep -qm1 "6\.12\.23-android16-5" && echo x' _ {} \; 2>/dev/null | wc -l)
    a17=$(find "$dir" -name "*.ko" -exec sh -c \
        'strings -a "$1" 2>/dev/null | grep -qm1 "6\.12\.69-android16-6" && echo x' _ {} \; 2>/dev/null | wc -l)
    printf "  %-52s 共 %3d   旧世代 %3d   新世代 %3d\n" "${dir#$P/}" "$n" "$a16" "$a17"
done

if [ "$DRY" -eq 1 ]; then
    echo
    echo "（--dry-run：不执行删除）"
    exit 0
fi

echo
echo "=== 删除残留 ==="
for d in vendor_dlkm vendor_ramdisk system_dlkm; do
    if [ -e "$P/$d" ]; then
        rm -rf "$P/$d"
        echo "  已删 $P/$d"
    fi
done
for f in vendor_dlkm.img system_dlkm.img vendor_boot.img; do
    if [ -e "$P/$f" ]; then
        rm -f "$P/$f"
        echo "  已删 $P/$f"
    fi
done

echo
echo "=== 清理后确认 ==="
ls -d "$P"/vendor_dlkm "$P"/vendor_ramdisk "$P"/system_dlkm 2>/dev/null \
    || echo "  三个目录均已不存在"
echo "  下一步：重新编译，然后跑 verify_kernel_modules.sh 确认"
