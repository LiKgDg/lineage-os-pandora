#!/bin/bash
# =============================================================================
# verify_index_ref.sh —— 「整目录替换」验收：三处模块目录与参考构建逐字节相同
#
# 为什么存在
#   本项目的修复方案是整目录替换（vendor_ramdisk / vendor_dlkm / system_dlkm_flatten），
#   验收判据只有一句：三处与已知可启动的出货构建（PixelOS）对应目录**逐字节相同**。
#   已有的门禁都不覆盖这句话：
#     kmi-gate.sh C1   只看 module_layout CRC，不看 .ko 本体字节
#     kmi-gate.sh C2   只看 modules.load 的条目能否解析
#     kmi-gate.sh C4   只看索引文件，且一次只能对一组
#   而本项目已经踩过「文件名清单一致、内容 411 个不同」的坑，所以这里直接比全文 md5。
#
#   与 kmi-gate.sh --ref 的分工
#     kmi-gate.sh --ref   单集合、构建期、需要 kmod（顺带查 CRC）
#     本脚本              三处成组、验收期、纯 md5，不需要 kmod，Windows 侧也能跑
#
# 用法
#   bash scripts/maintain/verify_index_ref.sh \
#       --los /root/los24/out/target/product/pandora \
#       --ref /root/work/gstack/ref/pixelos
#
#   参考树只要够这三层即可：
#     <ref>/vendor_ramdisk/lib/modules
#     <ref>/vendor_dlkm/lib/modules
#     <ref>/system_dlkm/lib/modules        （或 system_dlkm/flatten/lib/modules）
#
# 退出码
#   0 三处全部逐字节相同
#   1 有差异（列出前几条）
#   2 用法错误或目录缺失
# =============================================================================
set -u

PROG=$(basename "$0")
LOS=""
REF=""
SHOW=8
# 构建副产品：随构建路径/时间变化，本来就不该参与逐字节比对
IGNORE_RE='(^|/)(modules\.order|modules\.builtin|modules\.builtin\.modinfo)$'

while [ $# -gt 0 ]; do
    case "$1" in
        --los)        LOS="${2:-}"; shift 2 ;;
        --los=*)      LOS="${1#*=}"; shift ;;
        --ref)        REF="${2:-}"; shift 2 ;;
        --ref=*)      REF="${1#*=}"; shift ;;
        --show)       SHOW="${2:-8}"; shift 2 ;;
        -h|--help)    sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            echo "$PROG: 未知参数 $1" >&2; exit 2 ;;
    esac
done

[ -n "$LOS" ] && [ -n "$REF" ] || { echo "$PROG: 必须同时给 --los 与 --ref。用 --help 看用法。" >&2; exit 2; }
[ -d "$LOS" ] || { echo "$PROG: --los 目录不存在: $LOS" >&2; exit 2; }
[ -d "$REF" ] || { echo "$PROG: --ref 目录不存在: $REF" >&2; exit 2; }

hr() { printf '%s\n' "────────────────────────────────────────────────────────────────────────"; }

# 三处整目录替换的目标。每项：标签|LOS 侧相对路径|参考侧候选（用 : 分隔）
PAIRS=(
    "vendor_ramdisk|vendor_ramdisk/lib/modules|vendor_ramdisk/lib/modules"
    "vendor_dlkm|vendor_dlkm/lib/modules|vendor_dlkm/lib/modules"
    "system_dlkm_flatten|system_dlkm/flatten/lib/modules|system_dlkm_flatten/lib/modules:system_dlkm/flatten/lib/modules"
)

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

# 输出「md5<两个空格><相对路径>」，按路径排序；排除构建副产品
# 顺手把 Cygwin/Git Bash 的 `hash *name`（二进制模式）归一成 `hash  name`，
# 否则同一个脚本在 Windows 与 WSL 下会把文件名比成 "*x.ko" 与 "x.ko"。
list_md5() {
    local dir="$1" out="$2"
    ( cd "$dir" && find . -type f -printf '%P\n' 2>/dev/null \
        | grep -Ev "$IGNORE_RE" | LC_ALL=C sort \
        | tr '\n' '\0' | xargs -0 -r md5sum 2>/dev/null \
        | sed 's/^\([0-9a-f]\{32\}\) [ *]/\1  /' ) > "$out"
}

FAIL=0
TOTAL_SAME=0; TOTAL_DIFF=0; TOTAL_ONLY=0

for spec in "${PAIRS[@]}"; do
    IFS='|' read -r label los_rel ref_cands <<< "$spec"
    a="$LOS/$los_rel"

    hr
    echo "集合: $label"
    echo "  LOS : $a"

    if [ ! -d "$a" ]; then
        echo "  [FAIL] LOS 侧目录不存在 —— 三处替换缺了这一处"
        FAIL=1
        continue
    fi

    b=""
    IFS=':' read -r -a cands <<< "$ref_cands"
    for c in "${cands[@]}"; do
        [ -d "$REF/$c" ] && { b="$REF/$c"; break; }
    done
    if [ -z "$b" ]; then
        echo "  [FAIL] 参考侧三个候选路径都不存在：${ref_cands//:/ 或 }"
        FAIL=1
        continue
    fi
    echo "  参考: $b"

    list_md5 "$a" "$TMP/a"
    list_md5 "$b" "$TMP/b"
    na=$(wc -l < "$TMP/a"); nb=$(wc -l < "$TMP/b")

    # 按路径求交：same / diff / only 三类。
    read -r same diff only <<< "$(awk '
        FNR==NR { a[$2]=$1; next }
                { b[$2]=$1 }
        END {
            for (k in a) {
                if (!(k in b))       only++
                else if (a[k]!=b[k]) diff++
                else                 same++
            }
            for (k in b) if (!(k in a)) only++
            printf "%d %d %d\n", same, diff, only
        }' "$TMP/a" "$TMP/b")"

    printf "  文件数 : LOS %s / 参考 %s\n" "$na" "$nb"
    printf "  相同   : %s\n" "$same"
    printf "  内容不同: %s\n" "$diff"
    printf "  仅一侧 : %s\n" "$only"

    # 差异样例（最多 SHOW 条）
    if [ "$diff" -gt 0 ] || [ "$only" -gt 0 ]; then
        FAIL=1
        awk -v lim="$SHOW" '
            FNR==NR { a[$2]=$1; next }
                    { b[$2]=$1 }
            END {
                n=0
                for (k in a) {
                    if (!(k in b))          { printf "        仅 LOS  : %s\n", k; if (++n>=lim) exit }
                    else if (a[k]!=b[k])    { printf "        内容不同: %-40s %s ≠ %s\n", k, substr(a[k],1,8), substr(b[k],1,8); if (++n>=lim) exit }
                }
                for (k in b) if (!(k in a)) { printf "        仅参考  : %s\n", k; if (++n>=lim) exit }
            }' "$TMP/a" "$TMP/b"
    else
        echo "  => PASS（逐字节相同）"
    fi

    TOTAL_SAME=$((TOTAL_SAME + ${same:-0}))
    TOTAL_DIFF=$((TOTAL_DIFF + ${diff:-0}))
    TOTAL_ONLY=$((TOTAL_ONLY + ${only:-0}))
done

hr
printf "汇总：相同 %s 个 / 内容不同 %s 个 / 仅一侧 %s 个\n" "$TOTAL_SAME" "$TOTAL_DIFF" "$TOTAL_ONLY"
if [ "$FAIL" -eq 0 ]; then
    echo "验收通过：三处模块目录与参考构建逐字节相同。"
else
    echo "验收未通过：整目录替换没有做到「逐字节相同」。"
    echo "  修法：bash scripts/maintain/replace_kernel_modules.sh --imgset <镜像目录> --apply"
    echo "  不要手工改索引、也不要只补缺的 .ko —— 那条路本项目走过，走不通。"
fi
exit "$FAIL"
