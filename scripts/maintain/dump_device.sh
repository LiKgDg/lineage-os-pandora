#!/bin/bash
# =============================================================================
# dump_device.sh —— 从设备侧取 dump 的两种方式（B: adb pull / C: 分区 dd）
#
# 为什么要单独一个脚本
#   本项目的主力取证路径是「全量 OTA」（A）：9.17 GB 的官方包解出 57 个分区，
#   离线、可复跑、不需要设备。但有两类东西 OTA 拿不到：
#     1) persist / devinfo / frp / modemst* / fsc / fsg 这类不出现在 payload 里的分区
#     2) 运行态（含用户数据、日志、当前挂载状态）
#   所以 B 和 C 不是替代品，是补充。三条路径的分工：
#
#     A  全量 OTA       离线，全部分区镜像，可复跑        → tools/payload_dump.py
#     B  adb pull       运行态文件树，需 shell 可读       → 本脚本 --mode pull
#     C  分区 dd        分区级镜像（含 OTA 不含的分区），需 root → 本脚本 --mode dd
#
# 权限现实（pandora 实测）
#   · /dev/block/by-name 可以 list（166 项），但**块设备读取 Permission denied**
#     → C 必须有 root（adb root 或 su），shell 身份做不到
#   · /vendor /odm /system_ext /product 的多数文件 shell 可读
#     → B 可做，但 root-only 文件会被跳过，脚本会把清单单独列出
#
# 用法
#   bash scripts/maintain/dump_device.sh --list
#   bash scripts/maintain/dump_device.sh --mode pull --trees "vendor/etc odm/etc"
#   bash scripts/maintain/dump_device.sh --mode pull                  # 全部五棵树
#   bash scripts/maintain/dump_device.sh --mode dd --parts persist,devinfo
#   bash scripts/maintain/dump_device.sh --mode dd --parts all --force
#
# 退出码
#   0 成功
#   1 部分失败（列出失败项）
#   2 前置不满足（无设备 / 无 root / 空间不足 / 参数错）
# =============================================================================
set -u

# Git Bash 会把 adb 的 /vendor/etc 这类参数改写成 Windows 路径
# （实测：adb: error: failed to stat remote object 'C:/Users/.../vendor/etc'）。
# 这两个变量在 Linux/WSL 下是无害的空设置。
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL="*"

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJ" || exit 2

ADB="./platform-tools/adb.exe"
CSV="docs/device-partitions.csv"
MODE=""
TREES="vendor odm system_ext product system"
PARTS=""
OUT=""
FORCE=0

# OTA(payload) 能覆盖的分区 —— 这些走 A 路径即可，dd 只在前两类需求下才需要
OTA_PARTS=" boot init_boot vendor_boot dtbo vbmeta vbmeta_system system system_ext product vendor odm vendor_dlkm system_dlkm mi_ext pvmfw recovery "

# 绝不能随手 dd 的分区：bootloader / 固件。读写都可能出事，仅 --force 且明确点名才放行
FW_PARTS=" abl xbl xbl_config xbl_ramdisk xbl_ramdump tz hyp devcfg uefi aop keymaster modem dsp bluetooth featenabler imagefv multiimgoem qupfw shrm vm-bootsys cpucp multiimgqti qtee mdtp logfs "

while [ $# -gt 0 ]; do
    case "$1" in
        --list)  MODE="list"; shift ;;
        --mode)  MODE="${2:-}"; shift 2 ;;
        --trees) TREES="${2:-}"; shift 2 ;;
        --parts) PARTS="${2:-}"; shift 2 ;;
        --out)   OUT="${2:-}"; shift 2 ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

info() { echo "$@"; }
err()  { echo "ERROR: $*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────────────────"; }
in_list() { case " $2 " in *" $1 "*) return 0;; *) return 1;; esac; }

# 远端路径要保持 /vendor 原样，本地路径要转成 Windows 形式 ——
# adb.exe 是 Windows 程序，MSYS_NO_PATHCONV=1 之后它不认 /tmp/xxx。
# WSL/Linux 下没有 cygpath，原样返回即可。
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi }

[ -x "$ADB" ] || { err "找不到 $ADB"; exit 2; }
DEVS=$("$ADB" devices 2>/dev/null | grep -c "device$")
[ "$DEVS" -eq 1 ] || { err "adb 设备数 = $DEVS，要求恰好 1 台"; exit 2; }

# 提权判定：两条路都试，先看 shell 本身能不能读块设备，再看 su 能不能。
# 这台设备实测 adb root 被系统设置关着，但 KernelSU 的 su 可用（context ksu），
# 所以只判「块设备可读」会把能做的事误判成不能做。
SU_MODE=0
ROOT_OK=0
has_root() {
    "$ADB" shell 'dd if=/dev/block/by-name/devinfo bs=512 count=1 >/dev/null 2>&1 && echo YES' 2>/dev/null | grep -q YES
}
has_su() {
    n=$("$ADB" shell "su -c 'dd if=/dev/block/by-name/devinfo bs=512 count=1 2>/dev/null | wc -c'" 2>/dev/null | tr -d '\r' | tr -dc '0-9')
    [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null
}
detect_root() {
    if has_root; then SU_MODE=0; ROOT_OK=1; return 0; fi
    if has_su;   then SU_MODE=1; ROOT_OK=1; return 0; fi
    ROOT_OK=0; return 1
}
# 按检测结果在设备上执行命令。命令串内部不能含双引号（本脚本里都不含）。
dev() {
    if [ "$SU_MODE" -eq 1 ]; then
        "$ADB" shell "su -c \"$1\""
    else
        "$ADB" shell "$1"
    fi
}

# ---------------------------------------------------------------------------
# --list：分区全景 + 该走哪条路径
# ---------------------------------------------------------------------------
if [ "$MODE" = "list" ]; then
    hr
    info "设备分区清单（$("$ADB" shell getprop ro.product.device 2>/dev/null | tr -d '\r')）"
    if detect_root; then
        [ "$SU_MODE" -eq 1 ] && info "root: 可用（su / KernelSU）" || info "root: 可用（adb root）"
    else
        info "root: 不可用 —— C 路径（dd）会被拦下"
    fi
    hr
    printf "  %-22s %12s  %-8s %s\n" 分区 大小 OTA覆盖 备注
    TMP=$(mktemp); trap 'rm -f "$TMP"' EXIT
    "$ADB" shell 'ls /dev/block/by-name' 2>/dev/null | tr -d '\r' | sort > "$TMP"

    N_OTA=0; N_NEED=0
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        # A/B 后缀统一成不带后缀的名字去查 OTA 覆盖
        base=$(printf '%s' "$p" | sed 's/_[ab]$//')
        sz=$(awk -F, -v k="$p" '$1==k{print $5}' "$CSV" 2>/dev/null)
        sz="${sz:--}"
        if in_list "$base" "$OTA_PARTS"; then
            cov="是"; note="可用 payload_dump.py"
            N_OTA=$((N_OTA + 1))
        elif in_list "$base" "$FW_PARTS"; then
            cov="否"; note="固件分区，禁止 dd"
        else
            cov="否"; note="只能 dd（需 root）"
            N_NEED=$((N_NEED + 1))
        fi
        printf "  %-22s %12s  %-8s %s\n" "$p" "$sz" "$cov" "$note"
    done < "$TMP"

    hr
    info "共 $(wc -l < "$TMP") 个分区：OTA 可覆盖 $N_OTA 个，需 dd 补 $N_NEED 个（OTA 不含）"
    exit 0
fi

# ---------------------------------------------------------------------------
# B: adb pull 运行态文件树
# ---------------------------------------------------------------------------
if [ "$MODE" = "pull" ]; then
    OUT="${OUT:-dump-device/$(date -u +%Y%m%dT%H%M%SZ)-pull}"
    mkdir -p "$OUT"
    hr
    info "[B] adb pull 运行态文件树 → $OUT"
    if detect_root && [ "$ROOT_OK" -eq 1 ]; then
        if [ "$SU_MODE" -eq 1 ]; then RIGHTS="su"; else RIGHTS="adb root"; fi
    else
        RIGHTS="shell（root-only 文件会被跳过）"
    fi
    info "    权限: $RIGHTS"

    for t in $TREES; do
        target="/$t"
        safe=$(printf '%s' "$t" | tr '/' '-')     # 日志名不能带 /，否则重定向直接失败
        dst="$OUT/$t"
        info "  == $t =="
        # 先统计设备侧文件总数，拉完对比，把「读不到的」显式列出来
        total=$("$ADB" shell "find $target -type f 2>/dev/null | wc -l" 2>/dev/null | tr -d '\r')
        mkdir -p "$(dirname "$dst")"
        rm -rf "$dst"
        # 目标不存在时 adb pull 会把源目录整个复制成该名字，正好得到 $OUT/<tree>
        if "$ADB" pull "$target" "$(win "$dst")" >"$OUT/.pull-$safe.log" 2>&1; then
            got=$(find "$dst" -type f 2>/dev/null | wc -l)
            printf "    设备 %s 个文件 → 拉回 %s 个" "${total:-?}" "$got"
            if [ "${total:-0}" -gt "$got" ] 2>/dev/null; then
                echo "  ⚠ 差 $((total - got)) 个（多为 root-only，见 .pull-$safe.log）"
                grep -c "Permission denied" "$OUT/.pull-$safe.log" 2>/dev/null | sed 's/^/    权限拒绝行数: /'
            else
                echo "  OK"
            fi
        else
            echo "    FAILED（见 .pull-$safe.log）"
        fi
    done

    "$ADB" shell getprop > "$OUT/getprop.txt" 2>/dev/null
    "$ADB" shell 'mount' > "$OUT/mount.txt" 2>/dev/null
    info
    info "  已附：getprop.txt / mount.txt"
    info "  提示：pull 出来的是运行态文件树，不是分区镜像；要与 A 路径的镜像比对时注意大小写与符号链接差异"
    exit 0
fi

# ---------------------------------------------------------------------------
# C: 分区 dd
# ---------------------------------------------------------------------------
if [ "$MODE" = "dd" ]; then
    detect_root || {
        err "本机取不到 root（adb root 关闭、su 不可用），块设备读取被拒，C 路径无法执行。"
        err
        err "  开启方式（二选一）："
        err "    1) 设置 → 系统 → 开发者选项 → 打开「Root 调试」→ adb root"
        err "    2) 装 KernelSU/Magisk 后用 su，本脚本会走 su 分支（当前设备未见 su）"
        err
        err "  若只是想补 blobs：不需要 C，走 A（tools/payload_dump.py）+ "
        err "  scripts/maintain/extract_blobs_from_ota.sh 即可。"
        exit 2
    }
    if [ "$SU_MODE" -eq 1 ]; then info "  提权方式: su（KernelSU/Magisk）"; else info "  提权方式: adb root"; fi

    OUT="${OUT:-dump-device/$(date -u +%Y%m%dT%H%M%SZ)-dd}"
    mkdir -p "$OUT"
    hr
    info "[C] 分区 dd → $OUT"

    # 默认只做 OTA 不含的分区；--parts all 才全做（需 --force）
    if [ -z "$PARTS" ]; then
        PARTS=$("$ADB" shell 'ls /dev/block/by-name' 2>/dev/null | tr -d '\r' \
            | sed 's/_[ab]$//' | sort -u \
            | while read -r p; do
                in_list "$p" "$OTA_PARTS" || in_list "$p" "$FW_PARTS" || echo "$p"
              done | tr '\n' ',' | sed 's/,$//')
        info "  未指定 --parts，默认取 OTA 不含的分区: $PARTS"
    fi
    [ "$PARTS" = "all" ] && PARTS=$("$ADB" shell 'ls /dev/block/by-name' 2>/dev/null | tr -d '\r' | tr '\n' ',' | sed 's/,$//')

    # 空间检查
    avail=$("$ADB" shell 'df -k /data' 2>/dev/null | tail -1 | awk '{print $(NF-2)}')
    info "  设备 /data 可用: $((avail / 1024)) MiB"
    info "  （镜像先落 /data/local/tmp 再 pull，脚本会逐个清理）"

    FAIL=0; DONE=0; SKIPPED=0
    IFS=',' read -r -a LIST <<< "$PARTS"
    for p in "${LIST[@]}"; do
        p=$(printf '%s' "$p" | tr -d ' ')
        [ -z "$p" ] && continue
        base=$(printf '%s' "$p" | sed 's/_[ab]$//')

        if in_list "$base" "$FW_PARTS" && [ "$FORCE" -eq 0 ]; then
            info "  [跳过] $p —— 固件分区，误写不可恢复（要强行做请加 --force 并想清楚）"
            SKIPPED=$((SKIPPED + 1)); continue
        fi
        if in_list "$base" "$OTA_PARTS" && [ "$FORCE" -eq 0 ] && [ "$PARTS" != "all" ]; then
            info "  [跳过] $p —— OTA 已覆盖，走 A 路径更省（要强行做加 --force）"
            SKIPPED=$((SKIPPED + 1)); continue
        fi

        sz=$(dev "blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null" | tr -d '\r')
        if [ -z "$sz" ] || [ "$sz" -le 0 ] 2>/dev/null; then
            err "  [失败] $p —— 取不到分区大小"
            FAIL=$((FAIL + 1)); continue
        fi
        need_mb=$((sz / 1048576 + 8))
        if [ "${avail:-0}" -lt $((need_mb * 1024)) ] 2>/dev/null; then
            err "  [失败] $p —— 空间不足（需 ${need_mb} MiB）"
            FAIL=$((FAIL + 1)); continue
        fi

        printf "  %-18s %8s MiB  " "$p" "$((sz / 1048576))"
        # dd 后用 root chmod 644：su 写出的文件默认 root-only，shell 身份的 adb pull 读不到
        if dev "dd if=/dev/block/by-name/$p of=/data/local/tmp/dump-$p.img bs=4M 2>/dev/null && sync && chmod 644 /data/local/tmp/dump-$p.img" >/dev/null 2>&1; then
            if "$ADB" pull "/data/local/tmp/dump-$p.img" "$(win "$OUT/$p.img")" >/dev/null 2>&1; then
                got=$(stat -c %s "$OUT/$p.img" 2>/dev/null || echo 0)
                dev "rm -f /data/local/tmp/dump-$p.img" >/dev/null 2>&1
                if [ "$got" = "$sz" ]; then
                    echo "OK  $(sha256sum "$OUT/$p.img" | cut -c1-16)"
                    DONE=$((DONE + 1))
                else
                    echo "大小不符（期望 $sz 实得 $got）"; FAIL=$((FAIL + 1))
                fi
            else
                echo "pull FAILED"; FAIL=$((FAIL + 1))
            fi
        else
            echo "dd FAILED"; FAIL=$((FAIL + 1))
        fi
    done

    hr
    info "完成 $DONE 个，跳过 $SKIPPED 个，失败 $FAIL 个"
    [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

err "必须指定 --list 或 --mode {pull|dd}。用 --help 看用法。"
exit 2
