#!/bin/bash
# =============================================================================
# make_fastboot_package.sh —— 生成 `fastboot -w update` 可直接消费的整包
#
# 为什么存在
#   LOS 默认只产出 recovery 刷机包（payload.bin），要用 `fastboot -w update` 必须
#   有「img 包」：根目录放 android-info.txt + fastboot-info.txt + 全部分区镜像。
#   本脚本从 out/ 的既有产物组装该包，不重新编译。
#
# 与 PixelOS 出货包的差异（有意为之）
#   PixelOS 的 Fastboot_*.zip 还带了 abl/xbl/tz/uefi 等 40+ 个固件分区。
#   LOS 不构建固件，本脚本也**不打包固件** —— 只刷 ROM 分区，不动 bootloader。
#   这更安全：固件分区刷错是不可逆的，而 ROM 分区刷错可以重刷。
#
# 产物
#   Fastboot_lineage_pandora-<YYYYMMDD>-<HHMM>.zip
#
# 用法
#   bash scripts/build/make_fastboot_package.sh              # 打包到 releases/
#   bash scripts/build/make_fastboot_package.sh -o <目录>     # 指定输出目录
#   bash scripts/build/make_fastboot_package.sh --dry-run     # 只校验不打包
# =============================================================================
set -u

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${PRODUCT_OUT:-/root/los24/out/target/product/pandora}"
DEST="$PROJ/releases"
DRY=0
BOARD_LIST=""

while [ $# -gt 0 ]; do
    case "$1" in
        -o|--out)       DEST="${2:-}"; shift 2 ;;
        --board-list)   BOARD_LIST="${2:-}"; shift 2 ;;
        --dry-run)      DRY=1; shift ;;
        -h|--help)      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)              echo "ERROR: 未知参数 $1" >&2; exit 2 ;;
    esac
done

err()  { echo "ERROR: $*" >&2; }
info() { echo "$@"; }

[ -d "$OUT" ] || { err "构建产物目录不存在：$OUT"; exit 3; }
[ -f "$OUT/android-info.txt" ]  || { err "缺 android-info.txt（先跑一次 m bacon）"; exit 3; }
[ -f "$OUT/fastboot-info.txt" ] || { err "缺 fastboot-info.txt（先跑一次 m bacon）"; exit 3; }

# ---------------------------------------------------------------------------
# 1. 从 fastboot-info.txt 解析需要打包的镜像
# ---------------------------------------------------------------------------
# 支持两种行：`flash <name>`、`flash --apply-vbmeta <name>`
MAPFILE=$(mktemp)
trap 'rm -f "$MAPFILE"' EXIT

awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*flash[[:space:]]/ {
        n = NF
        name = $n
        print name
    }
' "$OUT/fastboot-info.txt" | sort -u > "$MAPFILE"

N=$(wc -l < "$MAPFILE")
[ "$N" -gt 0 ] || { err "fastboot-info.txt 里没有 flash 行"; exit 3; }
info "[1] fastboot-info.txt 要求打包 $N 个分区镜像"

# super_empty.img 由 update-super 使用，不在 flash 行里
NEED_SUPER=0
grep -q "^update-super" "$OUT/fastboot-info.txt" && NEED_SUPER=1

# ---------------------------------------------------------------------------
# 2. 逐个校验存在性
# ---------------------------------------------------------------------------
MISSING=0
LIST=$(mktemp)
trap 'rm -f "$MAPFILE" "$LIST"' EXIT

while IFS= read -r name; do
    f="$OUT/$name.img"
    if [ -f "$f" ]; then
        printf "    %-20s %12s 字节\n" "$name.img" "$(stat -c %s "$f")"
        echo "$name" >> "$LIST"
    else
        printf "    %-20s 缺失\n" "$name.img"
        MISSING=$((MISSING+1))
    fi
done < "$MAPFILE"

if [ "$NEED_SUPER" -eq 1 ]; then
    if [ -f "$OUT/super_empty.img" ]; then
        printf "    %-20s %12s 字节（update-super）\n" "super_empty.img" "$(stat -c %s "$OUT/super_empty.img")"
    else
        printf "    %-20s 缺失（update-super 需要）\n" "super_empty.img"
        MISSING=$((MISSING+1))
    fi
fi

[ "$MISSING" -eq 0 ] || { err "$MISSING 个镜像缺失，无法打包"; exit 3; }

# ---------------------------------------------------------------------------
# 3. 打包
# ---------------------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M)
NAME="Fastboot_lineage_pandora-${TS}.zip"
mkdir -p "$DEST"
ZIP="$DEST/$NAME"

if [ "$DRY" -eq 1 ]; then
    info ""
    info "[2] dry-run：将打包为 $ZIP"
    info "    内容：android-info.txt + fastboot-info.txt + $N 个分区镜像$([ "$NEED_SUPER" -eq 1 ] && echo ' + super_empty.img')"
    exit 0
fi

STAGE=$(mktemp -d)
trap 'rm -f "$MAPFILE" "$LIST"; rm -rf "$STAGE"' EXIT

info ""
info "[2] 暂存到 $STAGE"

# ---------------------------------------------------------------------------
# android-info.txt 改写
#   构建系统生成的是 `board=canoe`（TARGET_BOARD_PLATFORM）。但 fastboot 解析
#   android-info.txt 时，`board=` 会被当作对 `getvar product` 的硬要求：
#       Checking 'product'  FAILED
#       Device product is 'pandora'.  Update requires 'canoe'.
#   而设备 product 是 pandora（机型代号），与平台代号 canoe 不等 → 直接拒刷。
#
#   改写为 `require board=<代号>|<平台>`（与 PixelOS 出货包同款写法），
#   让 pandora 与 canoe 都放行。可用 --board-list 覆盖。
# ---------------------------------------------------------------------------
DEVICE_CODE=$(basename "$OUT")
BOARD_VAL=$(grep -m1 '^board=' "$OUT/android-info.txt" 2>/dev/null | cut -d= -f2- | tr -d '[:space:]')

if [ -n "$BOARD_LIST" ]; then
    ACCEPT="$BOARD_LIST"
elif [ -n "$BOARD_VAL" ] && [ "$BOARD_VAL" != "$DEVICE_CODE" ]; then
    ACCEPT="${DEVICE_CODE}|${BOARD_VAL}"
elif [ -n "$BOARD_VAL" ]; then
    ACCEPT="$BOARD_VAL"
else
    ACCEPT="$DEVICE_CODE"
fi

{
    echo "require board=${ACCEPT}"
    # 保留原文件里除 board= 以外的行（如 version-baseband 等）
    grep -v '^board=' "$OUT/android-info.txt" 2>/dev/null || true
} > "$STAGE/android-info.txt"

info "    android-info.txt 改写：board=${BOARD_VAL:-<无>} → require board=${ACCEPT}"

cp "$OUT/fastboot-info.txt" "$STAGE/"
while IFS= read -r name; do
    # 用硬链接避免复制 3 GB+ 数据；跨设备时退化为复制
    ln "$OUT/$name.img" "$STAGE/$name.img" 2>/dev/null || cp "$OUT/$name.img" "$STAGE/$name.img"
done < "$LIST"
if [ "$NEED_SUPER" -eq 1 ]; then
    ln "$OUT/super_empty.img" "$STAGE/super_empty.img" 2>/dev/null || cp "$OUT/super_empty.img" "$STAGE/super_empty.img"
fi

info "[3] 压缩（deflate，与 PixelOS 出货包一致）"
( cd "$STAGE" && zip -q -r -6 "$ZIP" . ) || { err "zip 打包失败"; exit 4; }

# ---------------------------------------------------------------------------
# 4. 验证
# ---------------------------------------------------------------------------
info ""
info "[4] 验证"
ENTRIES=$(unzip -l "$ZIP" | tail -1 | awk '{print $2}')
HAS_INFO=$(unzip -l "$ZIP" | grep -c "android-info.txt")
HAS_FBINFO=$(unzip -l "$ZIP" | grep -c "fastboot-info.txt")

printf "    条目数      : %s\n" "$ENTRIES"
printf "    android-info: %s\n" "$([ "$HAS_INFO" -ge 1 ] && echo 有 || echo 缺)"
printf "    fastboot-info: %s\n" "$([ "$HAS_FBINFO" -ge 1 ] && echo 有 || echo 缺)"
printf "    大小        : %s\n" "$(du -h "$ZIP" | cut -f1)"

# 逐个确认 flash 行对应的 img 都在包里
BAD=0
while IFS= read -r name; do
    unzip -l "$ZIP" | grep -q " $name.img$" || { err "包内缺 $name.img"; BAD=$((BAD+1)); }
done < "$LIST"
[ "$BAD" -eq 0 ] || exit 1

info ""
info "✅ 完成：$ZIP"
info ""
info "刷入方式："
info "  fastboot -w update \"$ZIP\""
info "  （-w 会触发 fastboot-info.txt 里的 if-wipe erase userdata / metadata）"
