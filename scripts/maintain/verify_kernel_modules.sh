#!/bin/bash
# 刷机前静态校验：构建产物里的内核模块必须与内核同属一个 KMI 世代
#
# 背景：内核开了 CONFIG_MODVERSIONS，module_layout 的 CRC 是硬闸门。
# A16 模块（6.12.23）配 A17 内核（6.12.69）会在 load_module() 里被判 -ENOEXEC，
# first-stage init 拿不到存储/显示驱动、挂不上 /system，表现为卡第一屏或复位循环。
# 见 INC-PANDORA-LOS24-001。
#
# 判定交给 scripts/maintain/kmi-gate.sh（单一实现），本脚本只负责在 out/ 里
# 把四个模块目录找出来，避免「路径写死在别处、换了布局就漏查」。
#
# 用法：
#   ./verify_kernel_modules.sh                 # 用默认 out 路径（构建树模式，判据是 CRC）
#   ./verify_kernel_modules.sh --out /path/to/out/target/product/pandora
#   ./verify_kernel_modules.sh -q              # 只出汇总表
#   ./verify_kernel_modules.sh --strict-dup    # 把重复条目也当失败
#   ./verify_kernel_modules.sh --images DIR    # 镜像模式：直接查要刷的那几个 .img
#
# 两种模式的区别
#   构建树模式（--out）  判据是 module_layout 的 CRC，精确，但需要 out/ 目录
#   镜像模式（--images）  判据是镜像内旧世代 vermagic 字符串计数，粗但够用，
#                        不需要 root、不需要挂载，能在刷机前对「即将刷进去的东西」直接下判断
#                        已知正确的 stock 镜像该计数为 0，见 docs/los24-build-notes.md
#
# 退出码：0 通过 / 1 不通过 / 2 用法错误
set -u

PROG=$(basename "$0")
HERE=$(cd "$(dirname "$0")" && pwd)
GATE="$HERE/kmi-gate.sh"

# 默认仍指向既有构建机路径，可用 --out 覆盖
P=/root/los24/out/target/product/pandora
PASS_ARGS=()
IMAGE_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --out)      [ $# -ge 2 ] || { echo "$PROG: --out 需要参数" >&2; exit 2; }
                    P="$2"; shift 2 ;;
        --out=*)    P="${1#*=}"; shift ;;
        --images)   [ $# -ge 2 ] || { echo "$PROG: --images 需要参数" >&2; exit 2; }
                    IMAGE_DIR="$2"; shift 2 ;;
        --images=*) IMAGE_DIR="${1#*=}"; shift ;;
        -h|--help)  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)          PASS_ARGS+=("$1"); shift ;;
    esac
done

# ---------- 镜像模式 ----------
if [ -n "$IMAGE_DIR" ]; then
    [ -d "$IMAGE_DIR" ] || { echo "$PROG: 镜像目录不存在: $IMAGE_DIR" >&2; exit 2; }

    EXPECT_KMI=6.12.69-android16-6
    STALE_KMI=6.12.23-android16-5
    FAIL=0

    # 计数要能在 Git Bash 下跑：那里没有 binutils 的 strings，退回 grep -a
    count_kmi() {
        if command -v strings >/dev/null 2>&1; then
            strings -a "$2" | grep -c "$1"
        else
            grep -ac "$1" "$2" || true
        fi
    }

    echo "=== 镜像级 KMI 检查（$IMAGE_DIR）==="
    printf "  %-20s %10s %10s   %s\n" 镜像 旧世代 新世代 判定
    CHECKED=0
    for img in vendor_boot.img vendor_dlkm.img system_dlkm.img; do
        f="$IMAGE_DIR/$img"
        if [ ! -f "$f" ]; then
            printf "  %-20s %10s %10s   %s\n" "$img" - - "缺失，跳过"
            continue
        fi
        CHECKED=$((CHECKED + 1))
        # vendor_boot 的 ramdisk 是压缩的，计数会偏小但 >0 即可判
        stale=$(count_kmi "$STALE_KMI" "$f")
        fresh=$(count_kmi "$EXPECT_KMI" "$f")
        if [ "$stale" -gt 0 ]; then
            printf "  %-20s %10s %10s   %s\n" "$img" "$stale" "$fresh" "FAIL"
            FAIL=1
        else
            printf "  %-20s %10s %10s   %s\n" "$img" "$stale" "$fresh" "OK"
        fi
    done

    # 一个都没查到 = 目录给错了或镜像没导出。空集合过门禁没有意义，判失败。
    if [ "$CHECKED" -eq 0 ]; then
        echo
        echo "没找到任何 vendor_boot.img / vendor_dlkm.img / system_dlkm.img —— 目录给错了？"
        exit 2
    fi

    # 内核 banner：抓「换了内核但模块没换」
    if [ -f "$IMAGE_DIR/boot.img" ]; then
        if command -v strings >/dev/null 2>&1; then
            banner=$(strings -a "$IMAGE_DIR/boot.img" | grep -m1 "^Linux version" | awk '{print $3}')
        else
            # 退回 grep -a 时不能用 ^ 锚定：原始二进制里该串不在行首
            banner=$(grep -am1 "Linux version" "$IMAGE_DIR/boot.img" | awk '{print $3}')
        fi
        if [ -n "${banner:-}" ]; then
            case "$banner" in
                "$EXPECT_KMI"*) printf "  %-20s %s\n" 内核 "$banner  OK" ;;
                *)              printf "  %-20s %s\n" 内核 "$banner  与期望 $EXPECT_KMI 不符"
                                FAIL=1 ;;
            esac
        fi
    fi


    echo
    if [ "$FAIL" -eq 0 ]; then
        echo "镜像级检查通过 —— 可以刷机"
    else
        echo "镜像里仍有 $STALE_KMI 世代的模块 —— 不要刷，先跑 clean_stale_modules.sh 重编"
    fi
    exit "$FAIL"
fi

# ---------- 构建树模式 ----------
[ -x "$GATE" ] || { echo "$PROG: 找不到可执行的 $GATE" >&2; exit 2; }
[ -d "$P" ]    || { echo "$PROG: 构建产物目录不存在: $P" >&2; exit 2; }

# 依次尝试候选路径，取第一个存在的
pick_dir() {
    local c
    for c in "$@"; do
        [ -d "$c" ] && { echo "$c"; return 0; }
    done
    return 1
}

DIRS=()
add_dir() {
    local label="$1"; shift
    local d
    if d=$(pick_dir "$@"); then
        printf "  %-26s %s\n" "$label" "$d"
        DIRS+=("$d")
    else
        printf "  %-26s %s\n" "$label" "（不存在，跳过）"
    fi
}

echo "=== 定位模块目录（$P）==="
add_dir "vendor_ramdisk"      "$P/vendor_ramdisk/lib/modules" "$P/vendor_ramdisk"
add_dir "vendor_dlkm"         "$P/vendor_dlkm/lib/modules"    "$P/vendor_dlkm"
# system_dlkm 有两份：版本化目录（运行期主路径）与 flatten 副本（易被漏查）
KVER_DIR=$(find "$P/system_dlkm/lib/modules" -maxdepth 1 -type d -name '6.12.*' 2>/dev/null | head -1)
add_dir "system_dlkm/<ver>"   "${KVER_DIR:-$P/system_dlkm/lib/modules}" "$P/system_dlkm"
add_dir "system_dlkm/flatten" "$P/system_dlkm/flatten/lib/modules" "$P/system_dlkm/flatten"
echo

if [ ${#DIRS[@]} -eq 0 ]; then
    echo "没有找到任何模块目录 —— 可能还没编译，或 out 路径不对" >&2
    exit 2
fi

# 内核映像用于 banner 校验（抓「内核换了、模块没换」这一类半迁移）
KARGS=()
for k in "$P/kernel" "$P/boot.img"; do
    [ -f "$k" ] && { KARGS=(-K "$k"); break; }
done
[ ${#KARGS[@]} -eq 0 ] && echo "提示：未找到 kernel / boot.img，跳过内核 banner 校验" && echo

exec "$GATE" -R "${KARGS[@]}" "${PASS_ARGS[@]}" "${DIRS[@]}"
