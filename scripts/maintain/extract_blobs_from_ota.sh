#!/bin/bash
# =============================================================================
# extract_blobs_from_ota.sh —— 从原厂 OTA 解出的分区镜像补齐 vendor blobs
#
# 为什么存在
#   vendor/xiaomi/sm8850-common 的 proprietary/ 里有 211 条清单条目找不到实体
#   （1758 条里 12%）。直觉会以为「需要一台设备 dump」，实测不是：
#   全量 OTA 解出的 vendor/odm/system_ext/system 四个 EROFS 镜像里，
#   这 211 条有 206 条**就在里面**（97.6%），只是当初提取链没跑全。
#   剩下 5 条（mi_ext 1 / odm 2 / system 1 / vendor 1）原厂镜像里也没有，
#   属于上游清单来自别的机型或别的固件版本，不是本机缺件。
#
# 与设备 dump 的关系
#   本脚本走「OTA 路径」，不需要设备。设备 dump（adb pull / TWRP dd）只在
#   需要 persist/devinfo 这类 OTA 不含的分区、或要做运行态取证时才需要。
#
# 前置
#   分区镜像目录（默认 /d/WSL/out/pandora/stock-super）需含：
#     vendor.img odm.img system_ext.img system.img
#   由 tools/payload_dump.py 从全量 OTA 解出。
#   WSL 内核通常**没有 erofs 支持**，所以走 fsck.erofs 用户态提取，不 mount。
#
# 用法
#   bash scripts/maintain/extract_blobs_from_ota.sh                 # 只比对，不改动
#   bash scripts/maintain/extract_blobs_from_ota.sh --apply         # 把缺的补进 proprietary/
#   bash scripts/maintain/extract_blobs_from_ota.sh --images /path  # 指定镜像目录
#   bash scripts/maintain/extract_blobs_from_ota.sh --work /path    # 指定提取工作目录
#
# 退出码
#   0 比对完成（--apply 时为补齐成功）
#   1 有缺失但未加 --apply（只比对模式下恒为 0，此码保留）
#   2 用法错误 / 镜像缺失 / 工具缺失
# =============================================================================
set -u

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# 镜像目录默认自动探测：同一路径在 WSL 是 /mnt/d/...，在 Git Bash 是 /d/...
# 本脚本依赖 fsck.erofs（只在 WSL/Linux 有），所以优先 WSL 形式。
if [ -z "${IMAGES:-}" ]; then
    for c in /mnt/d/WSL/out/pandora/stock-super /d/WSL/out/pandora/stock-super; do
        [ -d "$c" ] && { IMAGES="$c"; break; }
    done
    IMAGES="${IMAGES:-/mnt/d/WSL/out/pandora/stock-super}"
fi
WORK="${WORK:-/root/work/blobs-extract}"
PARTS="vendor odm system_ext system"

# 构建树内的两个位置：清单在 device/，实体在 vendor/
DEVICE_DIR="${DEVICE_DIR:-/root/los24/device/xiaomi/sm8850-common}"
VENDOR_DIR="${VENDOR_DIR:-/root/los24/vendor/xiaomi/sm8850-common}"
MANIFEST="$DEVICE_DIR/proprietary-files.txt"
BLOBS="$VENDOR_DIR/proprietary"

DO_APPLY=0
while [ $# -gt 0 ]; do
    case "$1" in
        --images) IMAGES="${2:-}"; shift 2 ;;
        --work)   WORK="${2:-}";   shift 2 ;;
        --apply)  DO_APPLY=1; shift ;;
        -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

info() { echo "$@"; }
err()  { echo "ERROR: $*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────────────"; }

# ---------------------------------------------------------------------------
# 前置检查
# ---------------------------------------------------------------------------
command -v fsck.erofs >/dev/null 2>&1 || {
    err "找不到 fsck.erofs（erofs-utils）。安装：apt-get install erofs-utils"
    exit 2
}
[ -f "$MANIFEST" ] || { err "清单不存在：$MANIFEST"; exit 2; }
[ -d "$BLOBS" ]    || { err "blobs 目录不存在：$BLOBS"; exit 2; }

MISSING_IMG=0
for p in $PARTS; do
    if [ ! -f "$IMAGES/$p.img" ]; then
        err "缺镜像：$IMAGES/$p.img"
        MISSING_IMG=$((MISSING_IMG + 1))
    fi
done
[ "$MISSING_IMG" -eq 0 ] || exit 2

# ---------------------------------------------------------------------------
# 1. 提取（EROFS 用户态解包；WSL 内核无 erofs，不能用 mount）
# ---------------------------------------------------------------------------
hr
info "[1] 从分区镜像提取（$IMAGES）"
mkdir -p "$WORK"
for p in $PARTS; do
    img="$IMAGES/$p.img"
    dst="$WORK/$p"

    # 类型校验：EROFS 的 magic 在偏移 1024，字节序 e2 e1 f5 e0
    magic=$(od -An -tx1 -j1024 -N4 "$img" 2>/dev/null | tr -d ' \n')
    if [ "$magic" != "e2e1f5e0" ]; then
        err "  $p.img 不是 EROFS（magic=$magic），跳过"
        continue
    fi

    if [ -d "$dst" ] && [ "$(find "$dst" -type f 2>/dev/null | head -1)" ]; then
        info "  $p: 已提取（$(find "$dst" -type f | wc -l) 文件），跳过"
        continue
    fi

    rm -rf "$dst"; mkdir -p "$dst"
    printf "  %-12s " "$p"
    if fsck.erofs --extract="$dst" "$img" >/dev/null 2>&1; then
        echo "解出 $(find "$dst" -type f | wc -l) 文件"
    else
        echo "FAILED"
    fi
done

# ---------------------------------------------------------------------------
# 2. 比对
# ---------------------------------------------------------------------------
hr
info "[2] 比对清单与实体"
MPY=$(mktemp); trap 'rm -f "$MPY"' EXIT
cat > "$MPY" <<'PY'
import os, sys, collections
mf, base, stock = sys.argv[1], sys.argv[2], sys.argv[3]
total = 0; missing = []; found_in_stock = []; absent = []
per = collections.Counter(); per_s = collections.Counter(); per_a = collections.Counter()
for ln in open(mf, encoding="utf-8", errors="replace"):
    s = ln.strip()
    if not s or s.startswith("#"):
        continue
    s = s.lstrip("-").strip()
    for sep in (";", "|"):
        s = s.split(sep)[0]
    if not s:
        continue
    total += 1
    part = s.split("/")[0]
    if os.path.exists(os.path.join(base, s)):
        continue
    missing.append(s); per[part] += 1
    if stock and os.path.exists(os.path.join(stock, s)):
        found_in_stock.append(s); per_s[part] += 1
    else:
        absent.append(s); per_a[part] += 1
print("清单 %d 条   实体缺失 %d 条 (%.1f%%)" % (total, len(missing), 100.0*len(missing)/total))
if stock:
    print("  其中原厂镜像里存在（可从镜像补齐）: %d" % len(found_in_stock))
    print("  原厂镜像里也没有（清单非本机固件）: %d" % len(absent))
    print()
    print("  %-12s %8s %10s %8s" % ("分区", "缺失", "镜像中有", "确实没有"))
    for p in sorted(per):
        print("  %-12s %8d %10d %8d" % (p, per[p], per_s[p], per_a[p]))
sys.stdout.write("FILL\t" + "\t".join(found_in_stock) + "\n")
sys.stdout.write("ABSENT\t" + "\t".join(absent) + "\n")
PY

OUT=$(python3 "$MPY" "$MANIFEST" "$BLOBS" "$WORK")
echo "$OUT" | grep -vE "^(FILL|ABSENT)" | sed 's/^/  /'

FILL_LIST=$(echo "$OUT" | awk -F'\t' '$1=="FILL"{for(i=2;i<=NF;i++) if($i!="") print $i}')
ABSENT_LIST=$(echo "$OUT" | awk -F'\t' '$1=="ABSENT"{for(i=2;i<=NF;i++) if($i!="") print $i}')
N_FILL=$(printf '%s\n' "$FILL_LIST" | grep -c . || true)
N_ABSENT=$(printf '%s\n' "$ABSENT_LIST" | grep -c . || true)

# ---------------------------------------------------------------------------
# 3. 补齐（--apply）
# ---------------------------------------------------------------------------
hr
if [ "$DO_APPLY" -eq 0 ]; then
    info "[3] 未加 --apply，只比对不改动"
    info "    可从镜像补齐 $N_FILL 条；原厂也没有 $N_ABSENT 条"
    exit 0
fi

info "[3] 补齐 $N_FILL 条（--apply）"
COPIED=0; FAILED=0
printf '%s\n' "$FILL_LIST" | while IFS= read -r e; do
    [ -z "$e" ] && continue
    src="$WORK/$e"
    dst="$BLOBS/$e"
    [ -f "$src" ] || continue
    mkdir -p "$(dirname "$dst")"
    if cp -p "$src" "$dst"; then
        COPIED=$((COPIED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
done
# 上面的 while 在子 shell 里，重新统计一次结果
COPIED=$(printf '%s\n' "$FILL_LIST" | while IFS= read -r e; do [ -n "$e" ] && [ -f "$BLOBS/$e" ] && echo x; done | wc -l)

info "  已补齐：$COPIED 条"
info
info "下一步（必须，否则新补的文件不会被安装进 system 镜像）："
info "  cd $DEVICE_DIR && python3 setup-makefiles.py   # 或 vendor 侧的等价入口"
info "  然后重跑 make，确认 Android.mk / *-vendor.mk 里出现了新增文件"
[ "$N_ABSENT" -gt 0 ] && info "  另有 $N_ABSENT 条原厂镜像也没有，保持缺失（清单来自别的机型/固件版本）"
exit 0
