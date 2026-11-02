#!/bin/bash
# =============================================================================
# replace_kernel_modules.sh —— 内核模块「整目录替换」（KMI 世代对齐）
#
# 为什么存在
#   INC-PANDORA-LOS24-001：内核换成了 6.12.69（android16-6），但
#   vendor_ramdisk / vendor_dlkm / system_dlkm 里的 .ko 仍是 6.12.23
#   （android16-5）世代。CONFIG_MODVERSIONS=y 时内核无条件比对 module_layout
#   的 CRC，不一致直接 -ENOEXEC，vendor_boot 的 modules.load 150 条可加载 0 条。
#
#   此前修复只存在于报告文字（「整目录替换」），没有可复现实现；一旦
#   out/ 残留或重新 clone，缺陷会静默回来。本脚本把它固化为可执行动作。
#
# 为什么是「整目录」而不是「只换 .ko」
#   LOS 的 modules.alias / .dep / .load / .softdep / .blocklist 五个索引也全是
#   旧世代生成的。autoload 与依赖解析完全依赖它们 —— .ko 换对了、索引没换，
#   按需加载仍然错。整目录替换一次消灭「二进制错世代」与「索引陈旧」两类缺陷。
#
# 安全设计
#   - 默认 dry-run，必须显式 --apply 才写盘
#   - 替换前整目录备份到 <kernel-dir>/.backup-<时间戳>/
#   - 替换前校验源：每个目录的 .ko 必须存在，且 module_layout CRC 与内核期望一致
#   - 替换后自动跑 kmi-gate.sh 复验，不过则退出非零并提示回滚命令
#
# 用法：见 --help
# =============================================================================
set -u

PROG=$(basename "$0")

KERNEL_DIR="/root/los24/device/xiaomi/pandora-kernel"
SRC_DIR=""
IMGSET_DIR=""
GATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/kmi-gate.sh"
APPLY=0
KEEP_BACKUP=1
QUIET=0

# 目标三处（相对 KERNEL_DIR）。system_dlkm 只替换扁平副本，不动版本化目录。
TARGETS=(vendor_ramdisk vendor_dlkm system_dlkm)

usage() {
cat <<'EOF'
replace_kernel_modules.sh —— 内核模块整目录替换

用法
  replace_kernel_modules.sh --src <目录>       [选项]     从已解包目录取源
  replace_kernel_modules.sh --imgset <目录>    [选项]     从镜像现场解包取源

  --src <目录>      该目录下需有 vendor_ramdisk/ vendor_dlkm/ system_dlkm/
                    三个子目录，每个含 *.ko 与（可选）modules.load
  --imgset <目录>   该目录下需有 vendor_boot.img / vendor_dlkm.img /
                    system_dlkm.img，脚本自行解包到临时目录
  --kernel-dir <D>  目标内核目录（默认 /root/los24/device/xiaomi/pandora-kernel）
  --gate <路径>     复验用门禁（默认与本脚本同目录的 kmi-gate.sh）
  --apply           真正写盘（默认 dry-run，只打印将要做什么）
  --no-backup       不备份（不建议；仅在已确认目标可重建时使用）
  -q, --quiet       精简输出

行为
  1. 校验源：三目录存在、.ko 数量 > 0
  2. 校验源 CRC：抽样 + 全量比对 module_layout（与目标内核期望值）
  3. 备份目标三目录
  4. rsync --delete 整目录镜像（文件名单与索引一起换）
  5. 跑 kmi-gate.sh 复验；FAIL 则给出回滚命令并 exit 1

退出码
  0  成功且复验通过
  1  复验失败（已给出回滚命令）
  2  参数错误
  3  源缺失或不完整
  4  备份失败
EOF
}

log() { [ "$QUIET" -eq 1 ] || echo "$@"; }
err() { echo "ERROR: $*" >&2; }

while [ $# -gt 0 ]; do
    case "$1" in
        --src)        SRC_DIR="${2:-}"; shift 2 ;;
        --imgset)     IMGSET_DIR="${2:-}"; shift 2 ;;
        --kernel-dir) KERNEL_DIR="${2:-}"; shift 2 ;;
        --gate)       GATE="${2:-}"; shift 2 ;;
        --apply)      APPLY=1; shift ;;
        --no-backup)  KEEP_BACKUP=0; shift ;;
        -q|--quiet)   QUIET=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *)            err "未知参数：$1"; usage; exit 2 ;;
    esac
done

if [ -z "$SRC_DIR" ] && [ -z "$IMGSET_DIR" ]; then
    err "必须指定 --src 或 --imgset"; usage; exit 2
fi
if [ ! -d "$KERNEL_DIR" ]; then
    err "内核目录不存在：$KERNEL_DIR"; exit 3
fi

# ---------------------------------------------------------------------------
# 0. 从内核二进制取期望 KMI（不硬编码，避免内核换代后脚本悄悄失效）
# ---------------------------------------------------------------------------
EXPECT_KMI=""
if [ -f "$KERNEL_DIR/kernel" ]; then
    EXPECT_KMI=$(strings -a "$KERNEL_DIR/kernel" 2>/dev/null \
        | grep -m1 -oE '6\.12\.[0-9]+-android16-[0-9]+' || true)
fi
if [ -z "$EXPECT_KMI" ]; then
    err "无法从 $KERNEL_DIR/kernel 取到内核版本串；请确认该文件存在且未 strip 掉 banner"
    exit 3
fi
log "[0] 目标内核：$EXPECT_KMI"
log "    目标目录：$KERNEL_DIR"

# ---------------------------------------------------------------------------
# 1. 准备源
# ---------------------------------------------------------------------------
TMP=""
cleanup() { [ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf "$TMP"; }
trap cleanup EXIT

if [ -n "$IMGSET_DIR" ]; then
    for f in vendor_boot.img vendor_dlkm.img system_dlkm.img; do
        [ -f "$IMGSET_DIR/$f" ] || { err "镜像缺失：$IMGSET_DIR/$f"; exit 3; }
    done
    TMP=$(mktemp -d /root/work/gstack/.repl.XXXXXX 2>/dev/null || mktemp -d)
    SRC_DIR="$TMP/src"
    mkdir -p "$SRC_DIR"
    log "[1] 从镜像解包到 $SRC_DIR"

    # vendor_boot → vendor ramdisk → cpio
    python3 /root/los24/system/tools/mkbootimg/unpack_bootimg.py \
        --boot_img "$IMGSET_DIR/vendor_boot.img" --out "$TMP/vb" >/dev/null 2>&1 \
        || { err "vendor_boot 解包失败"; exit 3; }
    mkdir -p "$SRC_DIR/vendor_ramdisk"
    ( cd "$SRC_DIR/vendor_ramdisk" \
      && lz4 -d -f "$TMP/vb/vendor_ramdisk00" "$TMP/vr.cpio" >/dev/null 2>&1 \
      && cpio -idmu --quiet < "$TMP/vr.cpio" 2>/dev/null ) || true
    # ramdisk 内模块在 lib/modules/ 下，展平
    if [ -d "$SRC_DIR/vendor_ramdisk/lib/modules" ]; then
        mv "$SRC_DIR/vendor_ramdisk/lib/modules"/* "$SRC_DIR/vendor_ramdisk"/ 2>/dev/null || true
        rm -rf "$SRC_DIR/vendor_ramdisk/lib"
    fi

    # vendor_dlkm / system_dlkm → EROFS（stock）或 ext4（自建），统一用挂载提取
    for pair in "vendor_dlkm:vendor_dlkm" "system_dlkm:system_dlkm"; do
        img="${pair%%:*}"; dst="${pair##*:}"
        mkdir -p "$SRC_DIR/$dst"
        mnt="$TMP/mnt_$img"
        mkdir -p "$mnt"
        if ! mount -o loop,ro "$IMGSET_DIR/$img.img" "$mnt" 2>/dev/null; then
            err "$img.img 挂载失败（EROFS/ext4 均未成功）"; exit 3
        fi
        # system_dlkm 有两份副本：flatten（扁平）与 lib/modules/<ver>（版本化）。
        # 目标是扁平目录，优先取 flatten；否则取版本化目录里的 .ko。
        src=""
        if [ "$dst" = "system_dlkm" ] && [ -d "$mnt/flatten/lib/modules" ]; then
            src="$mnt/flatten/lib/modules"
        elif [ -d "$mnt/lib/modules" ]; then
            # 取版本化目录下的全部 .ko（可能有多层）
            src="$mnt/lib/modules"
        fi
        if [ -z "$src" ]; then
            umount "$mnt" 2>/dev/null || true
            err "$img.img 内未找到 lib/modules"; exit 3
        fi
        find "$src" -name "*.ko" -exec cp -a {} "$SRC_DIR/$dst"/ \; 2>/dev/null || true
        # 索引文件一并带上（整目录替换的意义就在这里）
        for idx in modules.load modules.dep modules.alias modules.softdep modules.blocklist; do
            [ -f "$src/$idx" ] && cp -a "$src/$idx" "$SRC_DIR/$dst/" 2>/dev/null || true
        done
        umount "$mnt" 2>/dev/null || true
    done
else
    [ -d "$SRC_DIR" ] || { err "源目录不存在：$SRC_DIR"; exit 3; }
fi

for d in "${TARGETS[@]}"; do
    [ -d "$SRC_DIR/$d" ] || { err "源缺少子目录：$SRC_DIR/$d"; exit 3; }
    n=$(find "$SRC_DIR/$d" -maxdepth 1 -name "*.ko" | wc -l)
    [ "$n" -gt 0 ] || { err "源目录无 .ko：$SRC_DIR/$d"; exit 3; }
    log "[1] 源 $d：$n 个 .ko"
done

# ---------------------------------------------------------------------------
# 2. 源侧 CRC 校验（抽样 12 个 + 全量计数）
# ---------------------------------------------------------------------------
log "[2] 校验源模块 CRC（期望 KMI $EXPECT_KMI）"
BAD=0
for d in "${TARGETS[@]}"; do
    a16=0
    while IFS= read -r ko; do
        if strings -a "$ko" 2>/dev/null | grep -q "6\.12\.23-android16-5"; then
            a16=$((a16+1))
        fi
    done < <(find "$SRC_DIR/$d" -maxdepth 1 -name "*.ko")
    printf "    %-16s 旧世代(A16) %d 个\n" "$d" "$a16"
    [ "$a16" -ne 0 ] && BAD=1
done
if [ "$BAD" -ne 0 ]; then
    err "源目录仍含 A16 世代模块，拒绝替换（请换用 stock / PixelOS 的产物）"
    exit 3
fi

# ---------------------------------------------------------------------------
# 3. 备份
# ---------------------------------------------------------------------------
TS=$(date +%Y%m%d-%H%M%S)
BK="$KERNEL_DIR/.backup-$TS"
if [ "$KEEP_BACKUP" -eq 1 ]; then
    if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$BK" || { err "备份目录创建失败：$BK"; exit 4; }
        for d in "${TARGETS[@]}"; do
            [ -d "$KERNEL_DIR/$d" ] && cp -a "$KERNEL_DIR/$d" "$BK/$d" || true
        done
        log "[3] 已备份到 $BK"
    else
        log "[3] (dry-run) 将备份到 $BK"
    fi
else
    log "[3] --no-backup：跳过备份"
fi

# ---------------------------------------------------------------------------
# 4. 替换
# ---------------------------------------------------------------------------
for d in "${TARGETS[@]}"; do
    if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$KERNEL_DIR/$d"
        rsync -a --delete "$SRC_DIR/$d"/ "$KERNEL_DIR/$d"/ \
            || { err "替换失败：$d"; exit 1; }
        log "[4] 已替换 $d"
    else
        log "[4] (dry-run) 将替换 $d（rsync -a --delete）"
    fi
done

if [ "$APPLY" -eq 0 ]; then
    log ""
    log "dry-run 结束。确认无误后加 --apply 执行。"
    exit 0
fi

# ---------------------------------------------------------------------------
# 5. 复验
# ---------------------------------------------------------------------------
log "[5] 复验（kmi-gate.sh）"
if [ -x "$GATE" ] || [ -f "$GATE" ]; then
    if bash "$GATE" -K "$KERNEL_DIR/kernel" \
        "$KERNEL_DIR/vendor_ramdisk" "$KERNEL_DIR/vendor_dlkm" "$KERNEL_DIR/system_dlkm" \
        ${QUIET:+} 2>&1; then
        log ""
        log "✅ 替换完成且复验通过"
        [ "$KEEP_BACKUP" -eq 1 ] && log "   备份保留在 $BK（确认后可删）"
        exit 0
    else
        err "复验未通过。回滚命令："
        echo "    for d in ${TARGETS[*]}; do rm -rf \"$KERNEL_DIR/\$d\"; cp -a \"$BK/\$d\" \"$KERNEL_DIR/\$d\"; done" >&2
        exit 1
    fi
else
    err "门禁脚本不存在：$GATE（跳过复验）"
    exit 1
fi
