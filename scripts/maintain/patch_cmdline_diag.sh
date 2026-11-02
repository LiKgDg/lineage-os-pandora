#!/bin/bash
# =============================================================================
# patch_cmdline_diag.sh —— 给内核 cmdline 追加「把挂死变成崩溃」的诊断参数
#
# 为什么这么做
#   2026-11-02 的 D4 失败是**挂住**而不是崩溃：normal boot 时 init 卡在某个 wait_for，
#   adbd 从未启动，USB 不枚举，设备反复重启。因为没崩，所以 mtdoops 不留记录。
#
#   排查过程中先误判过一次：以为 pstore 为空是 `console=ttynull` 关掉了控制台。
#   设备 dmesg 直接推翻了这个判断：
#       printk: legacy console [ramoops-1] enabled
#       pstore: Registered ramoops as persistent store backend
#   也就是说 ramoops console 一直是启用的，`console=ttynull` 只影响交互控制台。
#
#   既然 pstore 这条路原因未定，就走**已被证明可用**的那条：
#   oops 分区里的 8 条记录都是 mtdoops 写的，说明它只在 oops/panic 时触发。
#   于是把「挂住」转成「崩溃」——卡住的进程被判为 hung task 后触发 panic，
#   mtdoops 就会把栈落盘，下次进 recovery 用 extract_crash_logs.sh 即可读到。
#
#   可行性依据：现有 cmdline 里已经有 `sysctl.kernel.panic_on_rcu_stall=1`，
#   证明 `sysctl.` 前缀的 cmdline 机制在此内核上可用。
#
# 注意
#   `console=ttynull` / `mtdoops.*` 等 token **不在** BOARD_KERNEL_CMDLINE 里，
#   它们来自预编译内核自带的 bootconfig。本脚本只能**追加**，改不掉既有 token。
#   生效需要重编 boot 并重刷，不是一个即时动作。
#
# 用法
#   bash scripts/maintain/patch_cmdline_diag.sh --check    # 只看当前状态
#   bash scripts/maintain/patch_cmdline_diag.sh --apply    # 追加诊断参数（自动备份）
#   bash scripts/maintain/patch_cmdline_diag.sh --revert   # 撤销
#
# 退出码
#   0 成功 / 已是目标状态
#   1 未找到 BOARD_KERNEL_CMDLINE 块
#   2 前置不满足
# =============================================================================
set -u

MK="${MK:-/root/los24/device/xiaomi/sm8850-common/BoardConfigCommon.mk}"
A="sysctl.kernel.hung_task_panic=1"
B="sysctl.kernel.hung_task_timeout_secs=30"

MODE="check"
while [ $# -gt 0 ]; do
    case "$1" in
        --check)  MODE="check"; shift ;;
        --apply)  MODE="apply"; shift ;;
        --revert) MODE="revert"; shift ;;
        -h|--help) sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

info() { echo "$@"; }
err()  { echo "ERROR: $*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────────"; }

[ -f "$MK" ] || { err "找不到 $MK"; err "  用 MK=... 指定路径"; exit 2; }

hr
info "目标: $MK"

PY=${PYTHON:-python}
command -v "$PY" >/dev/null 2>&1 || PY=python3

"$PY" - "$MK" "$MODE" "$A" "$B" <<'PY'
import io, os, shutil, sys, time

mk, mode, a, b = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
lines = io.open(mk, encoding="utf-8").read().splitlines(True)

def block_range(ls):
    """定位 BOARD_KERNEL_CMDLINE := \\ ... 的连续块"""
    for i, l in enumerate(ls):
        if l.startswith("BOARD_KERNEL_CMDLINE"):
            j = i
            while j < len(ls):
                if not ls[j].rstrip().rstrip("\\").strip().endswith("\\"):
                    # 继续吃到没有续行符的那一行
                    if ls[j].rstrip().endswith("\\"):
                        j += 1
                        continue
                    break
                j += 1
            return i, j
    return None, None

i, j = block_range(lines)
if i is None:
    print("ERROR: 没找到 BOARD_KERNEL_CMDLINE 块")
    sys.exit(1)

present = any(a in l for l in lines) and any(b in l for l in lines)
print("  当前状态: %s" % ("已含诊断参数" if present else "未含诊断参数"))

if mode == "check":
    print("\n  块内容（第 %d-%d 行）:" % (i + 1, j + 1))
    for l in lines[i:j + 1]:
        print("    " + l.rstrip())
    sys.exit(0)

if mode == "apply":
    if present:
        print("  已是目标状态，不重复追加")
        sys.exit(0)
    bak = mk + ".bak-%s" % time.strftime("%Y%m%d%H%M%S")
    shutil.copy2(mk, bak)
    print("  已备份: %s" % bak)
    # 最后一行补续行符，再插入两行
    last = lines[j]
    if not last.rstrip().endswith("\\"):
        lines[j] = last.rstrip("\r\n") + " \\\n"
    ins = ["    %s \\\n" % a, "    %s\n" % b]
    lines[j + 1:j + 1] = ins
    io.open(mk, "w", encoding="utf-8", newline="\n").writelines(lines)
    print("  已追加:")
    for x in ins:
        print("    " + x.rstrip())
    sys.exit(0)

if mode == "revert":
    if not present:
        print("  没有需要撤销的参数")
        sys.exit(0)
    # 优先从备份还原：删行会留下续行符 \，往返不可能逐字节一致
    # （实测：删两行后 bootmonitor.fingerprint 那行残留 " \"，md5 对不上）。
    import glob
    baks = sorted(glob.glob(mk + ".bak-*"))
    if baks:
        shutil.copy2(baks[-1], mk)
        print("  已从备份还原: %s" % baks[-1])
        sys.exit(0)
    out = [l for l in lines if a not in l and b not in l]
    for k in range(len(out) - 1, -1, -1):
        if out[k].strip() and "BOARD_KERNEL_CMDLINE" not in out[k]:
            if out[k].rstrip().endswith("\\"):
                out[k] = out[k].rstrip()[:-1].rstrip() + "\n"
            break
    io.open(mk, "w", encoding="utf-8", newline="\n").writelines(out)
    print("  已撤销诊断参数（无备份可用，走删行路径）")
    sys.exit(0)
PY
RC=$?

hr
if [ "$MODE" = "apply" ] && [ "$RC" -eq 0 ]; then
    info "下一步（本脚本不代做）："
    info "  1. 重编 boot：m bootimage（或整包 m bacon）"
    info "  2. 只刷 boot：fastboot flash boot out/target/product/pandora/boot.img"
    info "  3. 起来后若仍挂住，hung task 30 秒后会 panic → mtdoops 落盘"
    info "  4. 进 recovery 跑 scripts/maintain/extract_crash_logs.sh 取栈"
    info "  撤销：bash $0 --revert"
fi
exit $RC
