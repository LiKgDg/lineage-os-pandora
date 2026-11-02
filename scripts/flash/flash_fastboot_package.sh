#!/bin/bash
# =============================================================================
# flash_fastboot_package.sh —— 刷 fastboot 整包（fastboot -w update）
#
# 为什么存在
#   本项目的主刷机路径已从「逐分区 fastboot flash」换成「整包 fastboot -w update」：
#   整包里有 fastboot-info.txt，它会 update-super、按正确顺序刷逻辑分区，并执行
#   if-wipe erase userdata / metadata。逐分区脚本（flash_los_full.sh）不 wipe、
#   不走 update-super、也不刷 pvmfw —— 首次启动验收用它等于丢掉一半前提。
#
#   代价是整包路径上有三个只能靠脚本拦的陷阱：
#     T1 老版 fastboot 解析不了 fastboot-info.txt 会**静默降级**：super 不更新、
#        data 不擦、vbmeta 不施加，屏幕上一切正常。本项目已发生过同类失败。
#     T2 legacy 路径会遍历 zip 里所有 *.img 逐个 flash。LOS 包只有 ROM 分区无妨，
#        同一套命令拿去刷带 abl/xbl/tz/uefi 的第三方包就会写 bootloader。
#     T3 wipe 是否真发生没有任何返回值，只有日志里的 Erasing 'userdata' 算数。
#
#   本脚本把这三条做成硬闸，并把 pstore 基线、wipe 金丝雀一起做完。
#   见 INC-PANDORA-LOS24-001。
#
# 用法
#   bash scripts/flash/flash_fastboot_package.sh                    # 用 releases/ 里最新的整包
#   bash scripts/flash/flash_fastboot_package.sh --pkg <zip>
#   bash scripts/flash/flash_fastboot_package.sh --preflight        # 只过闸，不刷
#   bash scripts/flash/flash_fastboot_package.sh --check-log <log>  # 事后审计一份刷机日志
#   bash scripts/flash/flash_fastboot_package.sh --yes              # 不问
#
# 退出码
#   0 刷入且事后校验通过
#   1 事后校验失败（wipe 未发生 / 写了固件分区 / 关键行缺失 / 有 FAILED）
#   2 前置闸未通过（拒绝刷机）
#   3 用户取消
# =============================================================================
set -u

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJ" || exit 2

FB="./platform-tools/fastboot.exe"
ADB="./platform-tools/adb.exe"

PKG=""
DO_PREFLIGHT=0
CHECK_LOG=""
ASSUME_YES=0
USE_ADB=1

# 期望内核世代。与 scripts/maintain/verify_kernel_modules.sh 的判据保持一致。
EXPECT_KMI="6.12.69-android16-6"
STALE_KMI="6.12.23-android16-5"

# 固件分区黑名单：整包路径一旦写到这些分区，就必须立刻停手。
# 这些分区误刷不可回滚（部分需要 EDL + 授权账号）。
FW_BLACK="abl xbl xbl_config xbl_ramdisk xbl_ramdump tz hyp devcfg uefi aop keymaster modem dsp bluetooth featenabler imagefv multiimgoem qupfw shrm vm-bootsys cpucp multiimgqti qtee mdtp logfs"

FLASHED=0
while [ $# -gt 0 ]; do
    case "$1" in
        --pkg)       [ $# -ge 2 ] || { echo "$0: --pkg 需要参数" >&2; exit 2; }
                     PKG="$2"; shift 2 ;;
        --pkg=*)     PKG="${1#*=}"; shift ;;
        --preflight) DO_PREFLIGHT=1; shift ;;
        --check-log) [ $# -ge 2 ] || { echo "$0: --check-log 需要参数" >&2; exit 2; }
                     CHECK_LOG="$2"; shift 2 ;;
        --check-log=*) CHECK_LOG="${1#*=}"; shift ;;
        --no-adb)    USE_ADB=0; shift ;;
        -y|--yes)    ASSUME_YES=1; shift ;;
        -h|--help)   sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)           echo "$0: 未知参数 $1" >&2; exit 2 ;;
    esac
done

info() { echo "$@"; }
err()  { echo "ERROR: $*" >&2; }
hr()   { printf '%s\n' "────────────────────────────────────────────────────────────────"; }

# ---------------------------------------------------------------------------
# 定位整包：默认取 releases/ 里最新的 Fastboot_lineage_*.zip
# ---------------------------------------------------------------------------
pick_pkg() {
    local f
    f=$(ls -t releases/Fastboot_lineage_pandora-*.zip 2>/dev/null | head -1)
    [ -n "$f" ] || return 1
    echo "$f"
}
if [ -z "$PKG" ] && [ -z "$CHECK_LOG" ]; then
    PKG=$(pick_pkg) || { err "releases/ 下没有 Fastboot_lineage_pandora-*.zip，用 --pkg 指定"; exit 2; }
fi

# ---------------------------------------------------------------------------
# 分区白名单：以包内 fastboot-info.txt 为准，而不是写死 18 个名字。
# 这样「什么该刷」由构建产物自己声明，脚本只负责发现偏离。
# ---------------------------------------------------------------------------
WHITELIST=""
load_whitelist() {
    local pkg="$1"
    [ -f "$pkg" ] || return 1
    WHITELIST=$(unzip -p "$pkg" fastboot-info.txt 2>/dev/null \
        | awk '/^[[:space:]]*flash[[:space:]]/{print $NF}' | sort -u | tr '\n' ' ')
    # update-super 与 if-wipe 的分区不在 flash 行里，但会写盘
    WHITELIST="$WHITELIST super super_empty userdata metadata "
}
[ -n "$PKG" ] && load_whitelist "$PKG"

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ---------------------------------------------------------------------------
# 事后校验：从刷机日志判断「真的刷进去了、真的擦了、没碰固件分区」
# 这是 --check-log 与在线刷入共用的唯一实现。
# ---------------------------------------------------------------------------
post_check() {
    local log="$1" rc=0 n name bad=0 unknown=0

    if [ ! -f "$log" ]; then err "日志不存在：$log"; return 2; fi

    hr
    info "事后校验：$log"

    # T3：wipe 是否真发生
    for k in userdata metadata; do
        if grep -qF "Erasing '$k'" "$log"; then
            info "  [OK]   Erasing '$k' 出现"
        else
            err  "  [FAIL] 日志里没有 Erasing '$k' —— wipe 未发生，本次实验无效"
            rc=1
        fi
    done

    # super 必须被重写过，否则逻辑分区还是上一套
    if grep -qE "Sending sparse 'super'|update-super|Resizing 'super'" "$log"; then
        info "  [OK]   super 已重写"
    else
        err  "  [FAIL] 没有 super 的写入痕迹 —— fastboot 可能没解析 fastboot-info.txt"
        rc=1
    fi

    # T2：实际写了哪些分区
    # 大分区是 `Sending sparse '<name>'` 发的，只匹配 `Sending '<name>'` 会把
    # system / vendor / product 全漏掉 —— 那正是最该被审计的几个。
    n=0
    for name in $(grep -oE "Sending (sparse )?'[A-Za-z0-9_]+'" "$log" \
                  | sed "s/Sending sparse '//; s/Sending '//; s/'$//" | sort -u); do
        n=$((n + 1))
        if in_list "$name" "$FW_BLACK"; then
            err "  [致命] 写了固件分区 '$name' —— 立刻停止一切后续操作"
            bad=$((bad + 1)); rc=1
        elif [ -n "$WHITELIST" ] && ! in_list "$name" "$WHITELIST"; then
            info "  [注意] 写了白名单外的分区 '$name'"
            unknown=$((unknown + 1))
        fi
    done
    info "  实际写入分区：$n 个$([ "$bad" -gt 0 ] && echo "（其中固件分区 $bad 个）")$([ "$unknown" -gt 0 ] && echo "（白名单外 $unknown 个）")"

    if grep -q "FAILED" "$log"; then
        err "  [FAIL] 日志里有 FAILED —— 刷入没有全部成功"
        grep -n "FAILED" "$log" | head -5 | sed 's/^/         /'
        rc=1
    else
        info "  [OK]   无 FAILED"
    fi

    hr
    if [ "$rc" -eq 0 ]; then
        info "事后校验通过。下一步：等设备起系统，再验 wipe 金丝雀（见脚本末尾提示）。"
    else
        err "事后校验未通过 —— 不要在这台设备上继续叠加刷机，先取证。"
    fi
    return "$rc"
}

# --check-log：只做事后审计，不碰设备
if [ -n "$CHECK_LOG" ]; then
    post_check "$CHECK_LOG"
    exit $?
fi

# ---------------------------------------------------------------------------
# 日志：全程 tee，事后可复核
# ---------------------------------------------------------------------------
mkdir -p docs/logs
TS=$(date -u +%Y%m%dT%H%M%SZ)
LOG="docs/logs/${TS}-flash-package.log"
exec > >(tee -a "$LOG") 2>&1
info "日志: $LOG"
info "整包: $PKG"
info

# ---------------------------------------------------------------------------
# G1 包结构
# ---------------------------------------------------------------------------
hr
info "[G1] 包结构与 wipe 指令"
[ -f "$PKG" ] || { err "整包不存在：$PKG"; exit 2; }

for f in android-info.txt fastboot-info.txt; do
    unzip -l "$PKG" 2>/dev/null | grep -q " $f\$" \
        && info "  [OK]   $f" \
        || { err "  [FAIL] 包内缺 $f —— 不是 fastboot 安装包"; exit 2; }
done

FBINFO=$(unzip -p "$PKG" fastboot-info.txt 2>/dev/null)
echo "$FBINFO" | grep -q "^if-wipe erase userdata" \
    && info "  [OK]   if-wipe erase userdata" \
    || { err "  [FAIL] fastboot-info.txt 里没有 if-wipe erase userdata —— -w 只会擦 metadata"; exit 2; }
echo "$FBINFO" | grep -q "^if-wipe erase metadata" \
    && info "  [OK]   if-wipe erase metadata" \
    || err "  [注意] 没有 if-wipe erase metadata"
echo "$FBINFO" | grep -q "^update-super" \
    && info "  [OK]   update-super" \
    || { err "  [FAIL] 没有 update-super —— 逻辑分区大小不会按本包重置"; exit 2; }

info "  白名单（取自包内 fastboot-info）: $(echo "$WHITELIST" | tr -s ' ')"

# ---------------------------------------------------------------------------
# G2 fastboot 必须能解析 fastboot-info.txt（T1 静默降级）
# ---------------------------------------------------------------------------
hr
info "[G2] fastboot 版本"
[ -x "$FB" ] || { err "找不到 $FB"; exit 2; }
FBVER=$("$FB" --version 2>/dev/null | head -1)
FBNUM=$(printf '%s' "$FBVER" | sed 's/[^0-9.]//g' | awk -F. '{print $1}')
info "  $FBVER"
if [ -z "${FBNUM:-}" ] || [ "$FBNUM" -lt 34 ] 2>/dev/null; then
    err "  [FAIL] fastboot 版本过低（主版本 ${FBNUM:-未知} < 34）"
    err "         老版 fastboot 会静默忽略 fastboot-info.txt：super 不更新、data 不擦、"
    err "         vbmeta 不施加，而屏幕与退出码都显示成功。换 platform-tools 34+ 再来。"
    exit 2
fi
info "  [OK]   主版本 $FBNUM ≥ 34，支持 fastboot-info.txt"

# ---------------------------------------------------------------------------
# G3 镜像级模块世代（流式扫，不解包不落盘）
# ---------------------------------------------------------------------------
hr
info "[G3] 镜像内模块世代（期望 $EXPECT_KMI）"
count_in_img() {   # $1=成员名 $2=匹配串
    unzip -p "$PKG" "$1" 2>/dev/null | grep -aoF "$2" | wc -l | tr -d ' '
}
FAIL3=0
printf "  %-20s %10s %10s   %s\n" 镜像 旧世代 新世代 判定
for img in vendor_boot.img vendor_dlkm.img system_dlkm.img; do
    unzip -l "$PKG" 2>/dev/null | grep -q " $img\$" || { printf "  %-20s %10s %10s   %s\n" "$img" - - "缺失，跳过"; continue; }
    stale=$(count_in_img "$img" "$STALE_KMI")
    fresh=$(count_in_img "$img" "$EXPECT_KMI")
    if [ "$stale" -gt 0 ]; then
        printf "  %-20s %10s %10s   %s\n" "$img" "$stale" "$fresh" "FAIL"
        FAIL3=1
    else
        printf "  %-20s %10s %10s   %s\n" "$img" "$stale" "$fresh" "OK"
    fi
done
[ "$FAIL3" -eq 0 ] || { err "  镜像里仍有 $STALE_KMI 世代的模块 —— 不要刷，先修构建"; exit 2; }

# ---------------------------------------------------------------------------
# G4 设备状态（--preflight 也做，只读）
# ---------------------------------------------------------------------------
hr
info "[G4] 设备状态"
DEVS=$("$FB" devices 2>/dev/null | grep -c "fastboot")
if [ "$DEVS" -ne 1 ]; then
    if [ "$DO_PREFLIGHT" -eq 1 ]; then
        info "  [跳过] fastboot 设备数 = $DEVS，--preflight 只验包与环境"
        "$FB" devices 2>/dev/null | sed 's/^/         /'
        SKIP_DEVICE=1
    else
        err "  [FAIL] fastboot 设备数 = $DEVS，要求恰好 1 台"
        "$FB" devices 2>/dev/null | sed 's/^/         /'
        exit 2
    fi
fi

if [ "${SKIP_DEVICE:-0}" -eq 0 ]; then

ISUSER=$("$FB" getvar is-userspace 2>&1 | grep -oE 'yes|no' | head -1)
if [ "$ISUSER" = "yes" ]; then
    err "  [FAIL] 设备在 fastbootd，整包必须在 bootloader 下发起（包内会自己 reboot fastboot）"
    exit 2
fi
info "  [OK]   在 bootloader（is-userspace=${ISUSER:-未知}）"

PRODUCT=$("$FB" getvar product 2>&1 | sed -n 's/^product: *//p' | head -1)
case "$PRODUCT" in
    pandora|canoe) info "  [OK]   product=$PRODUCT" ;;
    *)             err "  [FAIL] product=$PRODUCT，与 android-info 的 pandora|canoe 不符"; exit 2 ;;
esac

BATT=$("$FB" getvar battery-voltage 2>&1 | sed -n 's/^battery-voltage: *//p' | head -1)
if [ -n "${BATT:-}" ]; then
    # 阈值默认 4200 mV。这台机器是 4.5V 级电芯，77% 时约 4.04V——
    # 按 4200 卡等于要求冲到 90% 以上，对一次 10–20 分钟的刷写过度保守。
    # 需要时用 FLASH_MIN_MV 显式覆盖，默认值保持不变。
    MIN_MV="${FLASH_MIN_MV:-4200}"
    [ "$MIN_MV" != "4200" ] && info "  [NOTE] 电量阈值被 FLASH_MIN_MV 覆盖为 ${MIN_MV} mV（默认 4200）"
    if [ "$BATT" -ge "$MIN_MV" ] 2>/dev/null; then
        info "  [OK]   电量 ${BATT} mV"
    else
        err "  [FAIL] 电量 ${BATT} mV 偏低（<${MIN_MV}），全程 10–20 分钟，掉电即变砖风险"
        exit 2
    fi
fi

fi   # SKIP_DEVICE

# ---------------------------------------------------------------------------
# G5 pstore 基线 + wipe 金丝雀
# ---------------------------------------------------------------------------
hr
info "[G5] 证据基线"
ADB_OK=0
if [ "$USE_ADB" -eq 1 ] && "$ADB" shell true >/dev/null 2>&1; then
    ADB_OK=1
    info "  adb 可达 —— 采集 pstore 基线与 wipe 金丝雀"
    "$ADB" shell 'ls -l /sys/fs/pstore/ 2>/dev/null' | sed 's/^/    /'
    "$ADB" pull /sys/fs/pstore "docs/logs/${TS}-pstore-pre" >/dev/null 2>&1 \
        && info "    已拉取 pstore 基线 -> docs/logs/${TS}-pstore-pre/" \
        || info "    pstore 为空或不可读（不阻塞）"
    CANARY="WIPE_CANARY-${TS}"
    "$ADB" shell "echo C > /data/local/tmp/${CANARY}; echo C > /sdcard/${CANARY}" 2>/dev/null \
        && info "    金丝雀已投放：${CANARY}（/data/local/tmp 与 /sdcard 各一份）" \
        || info "    金丝雀投放失败（/data 未就绪？不阻塞）"
    "$ADB" shell 'df /data 2>/dev/null' | tail -1 | sed 's/^/    /'
else
    info "  adb 不可达 —— 跳过 pstore 基线与金丝雀"
    info "  提示：这两项不是刷机前提，但缺了就无法证明 wipe 真的发生、也无法分辨 panic 新旧"
fi

# ---------------------------------------------------------------------------
# 确认
# ---------------------------------------------------------------------------
hr
info "即将执行：$FB -w update $PKG"
info "  这会真的擦掉 userdata 与 metadata，不可逆。"
if [ "$DO_PREFLIGHT" -eq 1 ]; then
    info "  （--preflight：到此为止）"
    exit 0
fi
if [ "$ASSUME_YES" -eq 0 ]; then
    printf "继续？输入 YES："
    read -r ans
    [ "$ans" = "YES" ] || { info "已取消"; exit 3; }
fi

# ---------------------------------------------------------------------------
# 刷入
# ---------------------------------------------------------------------------
hr
info "[刷入] $(date -u +%Y-%m-%dT%H:%M:%SZ)"
START=$(date +%s)
"$FB" -w update "$PKG"
RC=$?
END=$(date +%s)
info "[刷入] fastboot 退出码 $RC，耗时 $((END - START)) 秒"
[ "$RC" -eq 0 ] || err "fastboot 自身返回非 0 —— 先看日志里的 FAILED 行"

# ---------------------------------------------------------------------------
# 事后校验
# ---------------------------------------------------------------------------
post_check "$LOG"
POST=$?
FLASHED=1

hr
info "下一步（设备正在首次启动，预期 3–20 分钟，含 dexopt）："
info "  1. 先确认动画是逐帧推进还是冻帧：间隔 10 秒连拍三张截图比 hash"
info "  2. adb 起来后验金丝雀："
info "       $ADB shell 'ls /data/local/tmp/WIPE_CANARY-* /sdcard/WIPE_CANARY-* 2>&1'"
info "     两个文件都不存在 = wipe 真的发生了"
info "  3. 失败取证用 scripts/maintain/ 下的门禁与 docs/ 里的判读表，不要叠加刷机"

[ "$POST" -eq 0 ] && exit 0
exit 1
