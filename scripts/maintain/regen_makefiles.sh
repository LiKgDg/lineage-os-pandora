#!/bin/bash
# =============================================================================
# regen_makefiles.sh —— 带闸的 setup-makefiles 包装器
#
# 为什么需要这个
#   vendor/xiaomi/sm8850-common 的 Android.bp 是**陈旧产物**：
#   清单 1758 条里有 211 条在磁盘上不存在，而当前 Android.bp 是更早某个时刻
#   （那 211 个文件还在的时候）生成的。直接跑 ./setup-makefiles.py 会：
#     1. 边读清单边重写 Android.bp
#     2. 读到第一个不存在的 .so 时抛 FileNotFoundError
#     3. 退出，而 Android.bp 已被写成半截
#   实测：747,836 → 89,523 → 23,316 字节，构建直接挂掉，且没有备份可回滚。
#
#   这个脚本把上面三步都堵住：先体检 → 强制备份 → 后验大小 → 失败自动还原。
#
# 用法
#   bash scripts/maintain/regen_makefiles.sh --check      # 只体检（有悬空则 exit 1）
#   bash scripts/maintain/regen_makefiles.sh              # 备份 → 重生成 → 后验
#   bash scripts/maintain/regen_makefiles.sh --force      # 明知有悬空也执行（不推荐）
#   bash scripts/maintain/regen_makefiles.sh --restore DIR# 从指定备份目录还原
#
# 退出码
#   0  成功（--check 时为「无悬空」）
#   1  --check 发现悬空条目
#   2  前置不满足：有悬空且未加 --force / 找不到清单或生成物 / 参数错
#   3  重生成失败，已自动从备份还原
# =============================================================================
set -u

DEVICE_DIR="${DEVICE_DIR:-/root/los24/device/xiaomi/sm8850-common}"
VENDOR_DIR="${VENDOR_DIR:-/root/los24/vendor/xiaomi/sm8850-common}"
MANIFEST="$DEVICE_DIR/proprietary-files.txt"
BP="$VENDOR_DIR/Android.bp"
BACKUP_ROOT="${BACKUP_ROOT:-/root/work}"

MODE="run"; FORCE=0; RESTORE_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check"; shift ;;
        --force)   FORCE=1; shift ;;
        --restore) MODE="restore"; RESTORE_DIR="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

info() { echo "$@"; }
err()  { echo "ERROR: $*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────────"; }

# 构建树在 WSL 的 /root/los24 下，Git Bash 里看不到。
# 与其报「清单不存在」让人以为是文件丢了，不如直接说清该在哪跑。
if [ ! -d "$DEVICE_DIR" ]; then
    err "找不到构建树：$DEVICE_DIR"
    err
    err "  本脚本要在 WSL 里跑（构建树在 /root/los24 下，Git Bash 看不到）。例如："
    err "    wsl.exe -u root -e bash -lc 'cd \"<仓库路径>\" && bash scripts/maintain/regen_makefiles.sh --check'"
    err "  或用环境变量指向别处的树：DEVICE_DIR=... VENDOR_DIR=... bash $0"
    exit 2
fi

[ -f "$MANIFEST" ] || { err "清单不存在：$MANIFEST"; exit 2; }
[ -f "$BP" ]       || { err "Android.bp 不存在：$BP"; exit 2; }
[ -x "$DEVICE_DIR/setup-makefiles.py" ] || { err "setup-makefiles.py 不可执行"; exit 2; }

# ---------------------------------------------------------------------------
# --restore：从备份目录还原
# ---------------------------------------------------------------------------
if [ "$MODE" = "restore" ]; then
    [ -d "$RESTORE_DIR" ] || { err "备份目录不存在：$RESTORE_DIR"; exit 2; }
    cp -a "$RESTORE_DIR"/Android.bp "$VENDOR_DIR"/ 2>/dev/null
    cp -a "$RESTORE_DIR"/*.mk "$VENDOR_DIR"/ 2>/dev/null
    info "已从 $RESTORE_DIR 还原："
    stat -c "  Android.bp %s 字节" "$BP"
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. 体检：清单条目 vs 磁盘实体
# ---------------------------------------------------------------------------
hr
info "[1] 清单体检"
SCAN=$(mktemp); trap 'rm -f "$SCAN"' EXIT
python3 - "$MANIFEST" "$VENDOR_DIR/proprietary" > "$SCAN" <<'PY'
import os, sys
mf, base = sys.argv[1], sys.argv[2]
tot = 0; miss = []
for ln in open(mf, encoding="utf-8", errors="replace"):
    s = ln.strip()
    if not s or s.startswith("#"):
        continue
    s = s.lstrip("-").strip()
    for sep in (";", "|"):
        s = s.split(sep)[0]
    if not s:
        continue
    tot += 1
    if not os.path.exists(os.path.join(base, s.split(":")[0])):
        miss.append(s)
print("TOTAL %d" % tot)
print("MISS %d" % len(miss))
for m in miss[:10]:
    print("  - %s" % m)
PY

TOTAL=$(awk '$1=="TOTAL"{print $2}' "$SCAN")
NMISS=$(awk '$1=="MISS"{print $2}' "$SCAN")
info "  清单条目 $TOTAL，磁盘缺失 $NMISS"

if [ "${NMISS:-0}" -gt 0 ]; then
    info "  缺失样例："
    awk '/^  - /{print "    "$2}' "$SCAN"
    [ "$NMISS" -gt 10 ] && info "    ……（共 $NMISS 条）"
fi

if [ "$MODE" = "check" ]; then
    if [ "$NMISS" -eq 0 ]; then
        info "结论：清单与磁盘一致，重生成是安全的"
        exit 0
    fi
    err "结论：有 $NMISS 条悬空，直接跑 setup-makefiles.py 会把 Android.bp 写成半截"
    exit 1
fi

if [ "$NMISS" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
    err
    err "拒绝执行：清单里 $NMISS 条在本机磁盘上不存在。"
    err "  setup-makefiles.py 会在读到第一个不存在的 .so 时崩溃，"
    err "  并把 Android.bp 写成半截（实测 747,836 → 89,523 字节）。"
    err
    err "  可选："
    err "    1) 先补齐这些文件（注意：补齐可能引入 soong 依赖问题，见文档）"
    err "    2) 从清单里注释掉它们，让清单与磁盘一致"
    err "    3) 确实要试：加 --force（本脚本仍会备份，失败会自动还原）"
    exit 2
fi

# ---------------------------------------------------------------------------
# 2. 备份
# ---------------------------------------------------------------------------
hr
BK="$BACKUP_ROOT/regen-backup-$(date +%H%M%S)"
mkdir -p "$BK"
cp -a "$BP" "$BK"/Android.bp || { err "备份 Android.bp 失败"; exit 2; }
cp -a "$VENDOR_DIR"/*.mk "$BK"/ 2>/dev/null
cp -a "$MANIFEST" "$BK"/proprietary-files.txt 2>/dev/null
for need in Android.bp Android.mk BoardConfigVendor.mk; do
    [ -f "$BK/$need" ] || { err "备份不完整：缺 $need，中止（未改动任何文件）"; exit 2; }
done
SIZE_BEFORE=$(stat -c %s "$BK/Android.bp")
info "[2] 已备份到 $BK"
info "    Android.bp $SIZE_BEFORE 字节 + $(ls "$BK"/*.mk 2>/dev/null | wc -l) 个 .mk + 清单"

# ---------------------------------------------------------------------------
# 3. 重生成（注意：必须是 ./ 直接执行，不能 python3 setup-makefiles.py）
# ---------------------------------------------------------------------------
hr
info "[3] 执行 ./setup-makefiles.py"
info "    （它是 43 字节 shebang 壳：#!./extract-files.py --regenerate_makefiles）"
# 注意：不能用 `cmd | tail` 再取 $? —— 那是 tail 的退出码，恒为 0。
# 先落日志、再取 rc、最后打印。
GENLOG=$(mktemp)
( cd "$DEVICE_DIR" && ./setup-makefiles.py ) > "$GENLOG" 2>&1
RC=$?
tail -5 "$GENLOG"
rm -f "$GENLOG"

SIZE_AFTER=$(stat -c %s "$BP" 2>/dev/null || echo 0)
info "    Android.bp：$SIZE_BEFORE → $SIZE_AFTER 字节"

# ---------------------------------------------------------------------------
# 4. 后验：体积骤降即视为被截断，自动还原
# ---------------------------------------------------------------------------
hr
if [ "$RC" -ne 0 ] || [ "$SIZE_AFTER" -lt $((SIZE_BEFORE / 2)) ]; then
    err "[4] 重生成失败或被截断（rc=$RC）"
    cp -a "$BK"/Android.bp "$VENDOR_DIR"/ && cp -a "$BK"/*.mk "$VENDOR_DIR"/ 2>/dev/null
    err "    已自动从 $BK 还原，当前 Android.bp $(stat -c %s "$BP") 字节"
    exit 3
fi

info "[4] 后验通过"
if [ "$SIZE_AFTER" -ne "$SIZE_BEFORE" ]; then
    info "    注意：体积有变化（$((SIZE_AFTER - SIZE_BEFORE)) 字节），属正常——"
    info "    重生成结果取决于清单与磁盘的实际一致性，与旧产物不同不代表出错。"
fi
info "    回滚命令：bash $0 --restore $BK"
exit 0
