#!/bin/bash
# =============================================================================
# extract_crash_logs.sh —— 从设备分区里取崩溃/启动日志
#
# 为什么需要
#   这台设备的内核 cmdline 是 `console=ttynull`，**控制台被关掉**，
#   所以 /sys/fs/pstore 永远是空的，拿不到任何 panic 栈。
#   真正的日志写在两个专用分区里（cmdline 里点了名）：
#       mtdoops.devname=/dev/block/by-name/oops         16 MB
#       bootmonitor.devname=/dev/block/by-name/blackbox 180 MB
#   2026-11-02 的 D4 失败就是因为没有这个工具，人工 dd + od + 手工提取
#   花了四五轮命令才拼出结论。
#
# 什么时候用
#   设备起不来但 **recovery 能进**（adb 显示 recovery 态）时最好用；
#   recovery 里 mount 不了 super 的逻辑分区，但 oops/blackbox 是物理分区，能直接读。
#
# 用法
#   bash scripts/maintain/extract_crash_logs.sh                # 只取 oops
#   bash scripts/maintain/extract_crash_logs.sh --with-blackbox # 另取 blackbox 前 8 MB
#   bash scripts/maintain/extract_crash_logs.sh --out DIR      # 指定输出目录
#
# 输出
#   <out>/<TS>-oops.bin        原始分区镜像
#   <out>/<TS>-oops.txt        按记录切分后的可读文本
#   <out>/<TS>-oops-summary.txt 每条记录的元信息汇总
#
# 退出码
#   0 取到并成功切分
#   1 取到但没有可识别记录
#   2 前置不满足（无设备 / 分区不存在 / 参数错）
# =============================================================================
set -u

export MSYS_NO_PATHCONV=1
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 2

ADB="${ADB:-./platform-tools/adb.exe}"
OUT=""; WITH_BLACKBOX=0; BLACKBOX_MB=8

while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT="${2:-}"; shift 2 ;;
        --with-blackbox) WITH_BLACKBOX=1; shift ;;
        --blackbox-mb) BLACKBOX_MB="${2:-8}"; shift 2 ;;
        -h|--help) sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

# python 若是 Windows 版，不认 /tmp 这类 MSYS 路径，传参前要转成 Windows 形式。
# WSL/Linux 下没有 cygpath，原样返回即可。
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi }

info() { echo "$@"; }
err()  { echo "ERROR: $*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────────"; }

[ -x "$ADB" ] || { err "找不到 $ADB"; exit 2; }
STATE=$("$ADB" devices | sed -n '2,$p' | grep -v '^$' | awk '{print $2}' | head -1)
[ -n "${STATE:-}" ] || { err "没有连接的设备"; exit 2; }
info "设备状态: $STATE"
[ "$STATE" = "recovery" ] || info "  提示：非 recovery 态也能读，但 recovery 下最稳"

TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT="${OUT:-docs/logs}"
mkdir -p "$OUT"

# ---------------------------------------------------------------------------
# 取 oops
# ---------------------------------------------------------------------------
hr
info "[1] 读取 oops 分区"
if ! "$ADB" shell "ls /dev/block/by-name/oops" >/dev/null 2>&1; then
    err "设备上没有 oops 分区；本工具只适用于带 mtdoops 的小米机型"
    exit 2
fi
SIZE=$("$ADB" shell "blockdev --getsize64 /dev/block/by-name/oops 2>/dev/null" | tr -d '\r')
info "  分区大小: ${SIZE:-未知} 字节"

BIN="$OUT/$TS-oops.bin"
"$ADB" exec-out "dd if=/dev/block/by-name/oops bs=1M 2>/dev/null" > "$BIN" 2>/dev/null
GOT=$(stat -c %s "$BIN" 2>/dev/null || echo 0)
info "  已保存: $BIN（$GOT 字节）"
[ "$GOT" -gt 0 ] || { err "读取失败，得到 0 字节"; exit 2; }

# ---------------------------------------------------------------------------
# 切分记录（按 ##FLAGS: 分块，提取可打印文本）
# ---------------------------------------------------------------------------
info "[2] 切分记录并提取文本"
PY=${PYTHON:-python}
command -v "$PY" >/dev/null 2>&1 || PY=python3
"$PY" - "$(win "$BIN")" "$(win "$OUT/$TS-oops.txt")" "$(win "$OUT/$TS-oops-summary.txt")" <<'PY'
import io, re, sys

binn, outtxt, outsum = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(binn, "rb").read()

# 可打印化：非可打印字节换行，尽量保住原结构
chars = []
for b in data:
    if 32 <= b < 127 or b in (9,):
        chars.append(chr(b))
    elif b in (10, 13):
        chars.append("\n")
    else:
        chars.append("\n")
raw = "".join(chars)
lines = [l.rstrip() for l in raw.splitlines()]

# 记录边界：##FLAGS:n
idx = [i for i, l in enumerate(lines) if l.startswith("##FLAGS:")]
records = []
for k, start in enumerate(idx):
    end = idx[k + 1] if k + 1 < len(idx) else len(lines)
    rec = [l for l in lines[start:end] if len(l) >= 8]
    if rec:
        records.append(rec)

def field(rec, key):
    for l in rec[:12]:
        if l.startswith(key):
            return l.split(":", 1)[1].strip()
    return ""

summary, body = [], []
for n, rec in enumerate(records, 1):
    flags = field(rec, "##FLAGS")
    ver = field(rec, "##VEISION") or field(rec, "##VERSION")
    bidx = field(rec, "## BOOT_INDEX")
    reason = field(rec, "##REBOOT REASON")
    mode = field(rec, "## BOOT MODE")
    types = sorted({l.split(":", 1)[1].strip() for l in rec if l.startswith("## LOG TYPE:")})
    # 真正的 panic 判据：内核格式的 panic 行，不是分区名里的 oops
    panics = [l for l in rec if re.search(r"Kernel panic|Internal error:|Unable to handle kernel", l)]
    summary.append({
        "n": n, "flags": flags, "ver": ver, "bidx": bidx,
        "reason": reason, "mode": mode, "types": ",".join(types),
        "panic": len(panics), "lines": len(rec),
    })
    body.append("########## 记录 %d ##########" % n)
    body.extend(rec)

io.open(outtxt, "w", encoding="utf-8", newline="\n").write("\n".join(body))

w = ["记录数: %d" % len(records), ""]
w.append("%-4s %-6s %-8s %-12s %-10s %-22s %-6s %s" % (
    "序", "FLAGS", "BOOT_IDX", "版本", "重启原因", "模式", "行数", "panic"))
for s in summary:
    ver = (s["ver"] or "-")[:12]
    w.append("%-4d %-6s %-8s %-12s %-10s %-22s %-6d %d" % (
        s["n"], s["flags"] or "-", s["bidx"] or "-", ver,
        (s["reason"] or "-")[:10], (s["mode"] or "-")[:22],
        s["lines"], s["panic"]))
if not records:
    w.append("（没有识别到 ##FLAGS: 记录）")
io.open(outsum, "w", encoding="utf-8", newline="\n").write("\n".join(w) + "\n")
print("\n".join(w))
PY
[ -s "$OUT/$TS-oops-summary.txt" ] || { err "切分未产出"; exit 1; }

# ---------------------------------------------------------------------------
# 可选：blackbox
# ---------------------------------------------------------------------------
if [ "$WITH_BLACKBOX" -eq 1 ]; then
    hr
    info "[3] 读取 blackbox 前 ${BLACKBOX_MB} MB"
    if "$ADB" shell "ls /dev/block/by-name/blackbox" >/dev/null 2>&1; then
        BB="$OUT/$TS-blackbox-head${BLACKBOX_MB}M.bin"
        "$ADB" exec-out "dd if=/dev/block/by-name/blackbox bs=1M count=$BLACKBOX_MB 2>/dev/null" > "$BB" 2>/dev/null
        info "  已保存: $BB（$(stat -c %s "$BB" 2>/dev/null || echo 0) 字节）"
    else
        info "  设备上没有 blackbox 分区，跳过"
    fi
fi

hr
info "完成。判读要点："
info "  · panic 列为 0 但设备起不来 → 是挂住不是崩溃，用户态卡在某个 wait_for"
info "  · 本机 cmdline 是 console=ttynull，pstore 永远为空，别在那儿找"
info "  · 记录全是 BOOT MODE:recovery 说明失败那次没产生 oops（没崩）"
exit 0
