#!/bin/bash
# =============================================================================
# kmi-gate.sh —— 构建期 KMI 一致性门禁
#
# 为什么存在
#   INC-PANDORA-LOS24-001：内核换成 6.12.69（android16-6），但 vendor_boot /
#   vendor_dlkm 里的 .ko 仍是 6.12.23（android16-5）世代。CONFIG_MODVERSIONS=y
#   时内核在 load_module() 里无条件比对 module_layout 的 CRC，不一致直接 -ENOEXEC，
#   vendor_boot 的 modules.load 150 条可加载 0 条 —— 刷了必然起不来。
#   这个错误 100% 可以在构建机上离线查出，不该用刷机次数去换。
#
# 查什么
#   C1   CRC：目录内每个 .ko 的 module_layout CRC 必须等于内核期望值   ← 硬门禁
#   C1b  vermagic：每个 .ko 的 vermagic 版本段应与期望 KMI 一致        ← 仅告警
#   C2   存在性：modules.load 的每条都必须在本目录内找到同名文件        ← 硬门禁
#   C3   唯一性：modules.load 不得有重复条目                            ← 仅告警
#   C4   索引世代：modules.* 索引必须与参考构建逐字节一致（--ref）      ← 启用即硬门禁
#   任一硬门禁不过即 exit 1。
#
# 为什么需要 C4
#   C1 只管 .ko，管不到 modules.alias / modules.dep / modules.softdep / modules.blocklist
#   这几份**由模块集生成的索引**。A16 生成的索引配 A17 模块，autoload 与依赖解析会
#   整体走错：.ko 全换对了照样起不来，而 C1/C2/C3 全 PASS —— 这正是本项目的第二个
#   独立缺陷源（见 README 关键结论第 10 条）。本机模块是固定预编译产物，正确做法是
#   与已知可启动的出货构建（PixelOS）逐字节对账，故 C4 用 md5 判等，不用启发式推导。
#
# 依赖：kmod（modprobe --dump-modversions / modinfo）、coreutils。Linux/WSL 下运行。
#
# ⚠ 本文件必须是 LF 换行。在 Windows 上编辑后若变成 CRLF，会报
#   "bash: $'\r': command not found"；修复：sed -i 's/\r$//' kmi-gate.sh
#
# 用法：见 --help
# =============================================================================
set -u

PROG=$(basename "$0")
DEFAULT_CRC="0x797f2b3e"                 # 6.12.69-android16-6-g43b5ab7e247d 的 module_layout
DEFAULT_KMI="6.12.69-android16-6"        # vermagic 前两段
EXPECT_CRC="$DEFAULT_CRC"
EXPECT_KMI="$DEFAULT_KMI"
LOAD_OVERRIDE=""
REF_DIR=""                               # --ref 时才做 C4
DO_LOAD=1
STRICT_DUP=0
STRICT_VMAGIC=0
QUIET=0
JOBS=8
KERNEL_IMG=""
SCAN_DEPTH="-maxdepth 1"                 # -R 时置空，改为递归
SHOW_LIMIT=8                             # 每类问题最多列几条样例
DIRS=()

usage() {
cat <<'EOF'
kmi-gate.sh —— 构建期 KMI 一致性门禁

用法
  kmi-gate.sh [选项] <模块目录>...

  <模块目录> 是扁平目录：*.ko 与（可选）modules.load 同级。
  LOS 构建树里通常是：
      $(KERNEL_PATH)/vendor_ramdisk
      $(KERNEL_PATH)/vendor_dlkm
      $(KERNEL_PATH)/system_dlkm_flatten
  可一次给多个目录，逐个出报表，任一硬门禁 FAIL 则整体非零退出。
  报表里的集合名取「最小唯一路径后缀」——两个都叫 modules 的目录会自动
  显示成 los/lib/modules 与 stock/lib/modules，不会混。

选项
  -c, --expect-crc CRC   内核期望的 module_layout CRC。默认 0x797f2b3e
                         （= 6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k）
  -k, --kmi PREFIX       期望 vermagic 版本段前缀。默认 6.12.69-android16-6。
                         用于 C1b 报表，也用于 -K 的内核 banner 比对。
  -K, --kernel FILE      额外校验：FILE 里必须出现 "Linux version <EXPECT_KMI>"。
                         抓「换了内核但没换模块」这一类半迁移。
  -l, --load FILE        显式指定 modules.load（仅当只给一个目录时有效）
  --ref DIR              参考模块目录，启用 C4：本目录的 modules.* 索引必须与 DIR 内
                         同名文件逐字节一致（md5）。用于「整目录替换」的验收，
                         只允许配一个模块目录。双方都有的文件才严格判等，
                         单侧存在的只告警。
  -n, --no-load          跳过 C2/C3，只做 C1/C1b 全量扫描
  -R, --recursive        递归扫描子目录里的 .ko。system_dlkm 的版本化目录是
                         lib/modules/<ver>/kernel/**/*.ko 的嵌套结构，不递归会扫到 0 个。
                         扁平目录（vendor_ramdisk / vendor_dlkm / flatten）用不用都一样。
  -s, --strict-dup       把 C3（重复条目）从 WARN 升为 FAIL
  -S, --strict-vermagic  把 C1b（vermagic）从 WARN 升为 FAIL
  -d, --dup-limit N      允许的重复条目数上限。默认 0（仅在 --strict-dup 下生效）
  -j, --jobs N           modprobe/modinfo 并行度。默认 8
  -q, --quiet            只打印汇总表，不列样例
  -h, --help             显示本帮助

为什么 C3（重复条目）默认 WARN
  实测：原厂 stock 的 vendor_dlkm modules.load 是 665 条 / 唯一 402 条 —— **原厂自己
  就有 263 条重复**，而原厂能正常开机。所以「重复」本身不阻塞启动（内核按模块名幂等
  处理），把它做成硬门禁会误杀合法配置。LOS 侧 569 条 / 唯一 374 条（195 重复）同理
  不是启动失败的原因，但它会让「清单条数看起来比实际多」，是本次事故里被反复误用的
  那种「看起来一致」。因此：默认 WARN（不改变退出码），自己生成的清单请加 --strict-dup。

为什么 C1b（vermagic）默认 WARN
  CONFIG_MODVERSIONS=y 时，内核 same_magic() 只比较 vermagic 第一个空格**之后**的
  标志位（"SMP preempt mod_unload modversions aarch64"），版本段被跳过。实测本机：
  模块 vermagic 是 "6.12.69-android16-6-4k ..."，而内核 banner 是
  "6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k"，版本段本来就不同且能正常
  加载。所以 vermagic 版本段不是判据，只作告警；真正卡住加载的是 C1 的 CRC。
  「内核换了模块没换」这个具体形态由 -K 直接抓内核 banner，不靠 C1b。

退出码
  0  全部通过
  1  有硬门禁不通过（拒绝出包 / 拒绝刷机）
  2  用法错误或环境缺依赖

示例
  # 构建后、打包前，卡在出包链上
  kmi-gate.sh -K out/target/product/pandora/boot.img \
      $(KERNEL_PATH)/vendor_ramdisk \
      $(KERNEL_PATH)/vendor_dlkm \
      $(KERNEL_PATH)/system_dlkm_flatten

  # 单独校验一个已解出的镜像模块集
  kmi-gate.sh /root/work/gstack/qa/sets/los-vb

  # 只查 CRC（目录里没有 modules.load）
  kmi-gate.sh -n /root/work/gstack/qa/sets/stock-sd-flat

  # 整目录替换的验收：索引必须与已知可启动的出货构建逐字节相同
  kmi-gate.sh --ref /root/work/gstack/qa/sets/pixelos-vd /root/work/gstack/qa/sets/los-vd

  # 自己生成的清单要求零重复
  kmi-gate.sh --strict-dup $(KERNEL_PATH)/vendor_ramdisk
EOF
}

# ---------- 参数 ----------
while [ $# -gt 0 ]; do
  case "$1" in
    -c|--expect-crc) EXPECT_CRC="${2:-}"; shift 2 ;;
    -k|--kmi)        EXPECT_KMI="${2:-}"; shift 2 ;;
    -K|--kernel)     KERNEL_IMG="${2:-}"; shift 2 ;;
    -l|--load)       LOAD_OVERRIDE="${2:-}"; shift 2 ;;
    --ref)           REF_DIR="${2:-}"; shift 2 ;;
    -n|--no-load)    DO_LOAD=0; shift ;;
    -R|--recursive)  SCAN_DEPTH=""; shift ;;
    -s|--strict-dup) STRICT_DUP=1; shift ;;
    -S|--strict-vermagic) STRICT_VMAGIC=1; shift ;;
    -d|--dup-limit)  DUP_LIMIT="${2:-0}"; shift 2 ;;
    -j|--jobs)       JOBS="${2:-8}"; shift 2 ;;
    -q|--quiet)      QUIET=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    --)              shift; while [ $# -gt 0 ]; do DIRS+=("$1"); shift; done ;;
    -*)              echo "$PROG: 未知选项 $1" >&2; usage >&2; exit 2 ;;
    *)               DIRS+=("$1"); shift ;;
  esac
done
DUP_LIMIT="${DUP_LIMIT:-0}"

[ ${#DIRS[@]} -eq 0 ] && { echo "$PROG: 至少要给一个模块目录。用 --help 看用法。" >&2; exit 2; }
command -v modprobe >/dev/null 2>&1 || { echo "$PROG: 找不到 modprobe（需 kmod）。" >&2; exit 2; }
[ -n "$LOAD_OVERRIDE" ] && [ ${#DIRS[@]} -ne 1 ] && { echo "$PROG: --load 只能配一个目录。" >&2; exit 2; }
# C4 是「一对一」对账：参考目录与被测目录必须指同一种集合（都 vendor_dlkm 或都 flatten），
# 多目录时无法判断谁对谁，与其猜不如拒绝。
[ -n "$REF_DIR" ] && [ ${#DIRS[@]} -ne 1 ] && { echo "$PROG: --ref 只能配一个模块目录。" >&2; exit 2; }
[ -n "$REF_DIR" ] && [ ! -d "$REF_DIR" ] && { echo "$PROG: 参考目录不存在: $REF_DIR" >&2; exit 2; }

# CRC 统一成小写 0x 前缀，避免 0x797F2B3E / 797f2b3e 之类写法差异造成假失败
norm_crc() { local c; c=$(printf '%s' "$1" | tr 'A-F' 'a-f'); case "$c" in 0x*) echo "$c";; "") echo "";; *) echo "0x$c";; esac; }
EXPECT_CRC=$(norm_crc "$EXPECT_CRC")

# Git Bash 有 md5sum，macOS 只有 md5 —— 两种环境都要能跑
md5_of() {
  if command -v md5sum >/dev/null 2>&1; then md5sum "$1" 2>/dev/null | awk '{print $1}'
  else md5 -q "$1" 2>/dev/null; fi
}

TMP=$(mktemp -d) || exit 2
trap 'rm -rf "$TMP"' EXIT

hr() { printf '%s\n' "────────────────────────────────────────────────────────────────────────"; }

# ---------- 集合标签：最小唯一路径后缀 ----------
# 两个目录都叫 .../lib/modules 时，标签会退化到 los/lib/modules 与 stock/lib/modules。
# 不做这件事，CI 报表里会出现两行同名的 modules —— 正是本次事故同类的「看起来一致」。
LABELS=()
compute_labels() {
  local n=${#DIRS[@]} k i m start j key comps dups
  for k in 1 2 3 4 5 6 7 8; do
    LABELS=()
    for i in $(seq 0 $((n - 1))); do
      local d="${DIRS[$i]%/}"
      IFS='/' read -r -a comps <<< "$d"
      m=${#comps[@]}
      start=$(( m > k ? m - k : 0 ))
      key=""
      for j in $(seq "$start" $((m - 1))); do
        key="${key:+$key/}${comps[$j]}"
      done
      [ -z "$key" ] && key="$d"
      LABELS+=("$key")
    done
    dups=$(printf '%s\n' "${LABELS[@]}" | sort | uniq -d)
    [ -z "$dups" ] && return 0
  done
  return 0
}
compute_labels

# ---------- C1 / C1b：全量扫描 ----------
# 输出每行 "basename<TAB>crc<TAB>vermagic版本段"；crc 为 NONE 表示没有 module_layout
scan_mods() {
  local dir="$1" out="$2"
  find "$dir" $SCAN_DEPTH -name '*.ko' -type f -print0 \
    | xargs -0 -r -P "$JOBS" -n 1 bash -c '
        c=$(modprobe --dump-modversions "$1" 2>/dev/null | awk "\$2==\"module_layout\"{print \$1}")
        v=$(modinfo -F vermagic "$1" 2>/dev/null | awk "{print \$1}")
        printf "%s\t%s\t%s\n" "${1##*/}" "${c:-NONE}" "${v:-NONE}"
      ' _ > "$out"
  sort -o "$out" "$out"
}

# ---------- 单个集合 ----------
FAILED_SETS=0
FAILED_C1=0; FAILED_C2=0; FAILED_C3=0; FAILED_C1B=0; FAILED_C4=0
ROWS=()

check_set() {
  local dir="$1" idx="$2" total="$3"
  local name="${LABELS[$idx]}"
  local crcfile="$TMP/crc.$idx"
  local n_ko=0 n_ok=0 n_bad=0 n_none=0 n_vm_ok=0 n_vm_bad=0
  local n_entries=0 n_uniq=0 n_dup=0 n_missing=0 loadpath="" c1_fail=0 c1b_fail=0 c3_fail=0 c4_fail=0
  local c4_same=0 c4_diff=0 c4_only=0

  hr
  if [ ! -d "$dir" ]; then
    echo "集合 $((idx + 1))/$total: $name  ——  目录不存在: $dir"
    FAILED_SETS=$((FAILED_SETS + 1)); FAILED_C1=$((FAILED_C1 + 1))
    ROWS+=("$name|ERR|0|0|0|0|0|-|缺失")
    return
  fi

  echo "集合 $((idx + 1))/$total: $name"

  # --- C1 / C1b ---
  scan_mods "$dir" "$crcfile"
  n_ko=$(wc -l < "$crcfile")
  n_ok=$(awk -F'\t' -v e="$EXPECT_CRC" '$2==e' "$crcfile" | wc -l)
  n_none=$(awk -F'\t' '$2=="NONE"' "$crcfile" | wc -l)
  n_bad=$((n_ko - n_ok))
  n_vm_ok=$(awk -F'\t' -v k="$EXPECT_KMI" 'index($3,k)==1' "$crcfile" | wc -l)
  n_vm_bad=$((n_ko - n_vm_ok))

  if [ "$n_ko" -eq 0 ]; then
    echo "  [C1]  CRC 一致        : 0 个 .ko —— 目录是空的，判 FAIL（空目录过门禁没有意义）"
    c1_fail=1
  elif [ "$n_bad" -eq 0 ]; then
    echo "  [C1]  CRC 一致        : $n_ok / $n_ko   PASS"
  else
    echo "  [C1]  CRC 一致        : $n_ok / $n_ko   FAIL —— $n_bad 个不符"
    c1_fail=1
  fi
  if [ "$n_ko" -gt 0 ]; then
    echo -n "        CRC 分布: "
    awk -F'\t' '{c[$2]++} END{for (k in c) printf "%s=%d  ", k, c[k]; print ""}' "$crcfile"
  fi
  if [ "$n_none" -gt 0 ]; then
    echo "        ⚠ $n_none 个 .ko 取不到 module_layout（不是内核模块？或 modprobe 读不了）"
    [ "$QUIET" -eq 0 ] && awk -F'\t' '$2=="NONE"{print "         "$1}' "$crcfile" | head -"$SHOW_LIMIT"
  fi
  if [ "$n_bad" -gt 0 ] && [ "$QUIET" -eq 0 ]; then
    echo "        不符样例（最多 $SHOW_LIMIT 条）:"
    awk -F'\t' -v e="$EXPECT_CRC" '$2!=e && $2!="NONE"{printf "         %-40s %s\n", $1, $2}' "$crcfile" | head -"$SHOW_LIMIT"
    [ "$n_bad" -gt "$SHOW_LIMIT" ] && echo "         ……（其余 $((n_bad - SHOW_LIMIT)) 个省略）"
  fi

  if [ "$n_ko" -gt 0 ]; then
    if [ "$n_vm_bad" -eq 0 ]; then
      echo "  [C1b] vermagic 版本段 : $n_vm_ok / $n_ko   PASS"
    elif [ "$STRICT_VMAGIC" -eq 1 ]; then
      echo "  [C1b] vermagic 版本段 : $n_vm_ok / $n_ko   FAIL —— $n_vm_bad 个不是 $EXPECT_KMI*（--strict-vermagic）"
      c1b_fail=1
    else
      echo "  [C1b] vermagic 版本段 : $n_vm_ok / $n_ko   WARN —— $n_vm_bad 个不是 $EXPECT_KMI*（不阻塞，见 --help）"
    fi
    echo -n "        vermagic 分布: "
    awk -F'\t' '{c[$3]++} END{for (k in c) printf "%s×%d  ", k, c[k]; print ""}' "$crcfile"
  fi

  # --- C2 / C3 ---
  if [ "$DO_LOAD" -eq 0 ]; then
    echo "  [C2]  条目可解析      : 跳过（--no-load）"
    echo "  [C3]  无重复条目      : 跳过（--no-load）"
  else
    if [ -n "$LOAD_OVERRIDE" ]; then
      loadpath="$LOAD_OVERRIDE"
    elif [ -f "$dir/modules.load" ]; then
      loadpath="$dir/modules.load"
    else
      loadpath=$(find "$dir" -maxdepth 4 -name modules.load -type f 2>/dev/null | head -1)
    fi

    if [ -z "$loadpath" ] || [ ! -f "$loadpath" ]; then
      echo "  [C2]  条目可解析      : 目录内无 modules.load —— 跳过（CRC-only 模式）"
      echo "  [C3]  无重复条目      : 跳过"
    else
      awk '{print $1}' "$loadpath" | grep -v '^#' | grep -v '^$' > "$TMP/e.$idx"
      n_entries=$(wc -l < "$TMP/e.$idx")
      n_uniq=$(sort -u "$TMP/e.$idx" | wc -l)
      n_dup=$((n_entries - n_uniq))
      # 清单条目可能是裸名（vendor_boot / flatten）也可能是 kernel/arch/... 相对路径
      # （system_dlkm 版本化目录）。先按相对路径精确判，失败再按 basename 判。
      awk -F'\t' '{print $1}' "$crcfile" | sort -u > "$TMP/have.$idx"
      : > "$TMP/miss.$idx"
      local n_pathstyle
      while IFS= read -r e; do
        [ -z "$e" ] && continue
        [ -e "$dir/$e" ] && continue
        grep -Fxq "${e##*/}" "$TMP/have.$idx" || printf '%s\n' "$e" >> "$TMP/miss.$idx"
      done < <(sort -u "$TMP/e.$idx")
      n_missing=$(wc -l < "$TMP/miss.$idx")
      n_pathstyle=$(grep -c '/' "$TMP/e.$idx" || true)

      echo "  [C2]  条目可解析      : $((n_entries - n_missing)) / $n_entries  " \
           "$([ "$n_missing" -eq 0 ] && echo PASS || echo "FAIL —— $n_missing 条悬空")"
      [ "$n_pathstyle" -gt 0 ] && echo "        其中 $n_pathstyle 条是相对路径写法（kernel/…），已按 basename 解析"
      if [ "$n_missing" -gt 0 ]; then
        FAILED_C2=$((FAILED_C2 + 1))
        [ "$QUIET" -eq 0 ] && sed 's/^/         悬空: /' "$TMP/miss.$idx" | head -"$SHOW_LIMIT"
        [ "$n_missing" -gt "$SHOW_LIMIT" ] && echo "         ……（其余 $((n_missing - SHOW_LIMIT)) 条省略）"
      fi

      if [ "$n_dup" -eq 0 ]; then
        echo "  [C3]  无重复条目      : 唯一 $n_uniq / $n_entries   PASS"
      elif [ "$STRICT_DUP" -eq 1 ] && [ "$n_dup" -gt "$DUP_LIMIT" ]; then
        echo "  [C3]  无重复条目      : 唯一 $n_uniq / $n_entries   FAIL —— $n_dup 条重复（--strict-dup）"
        c3_fail=1
        [ "$QUIET" -eq 0 ] && sort "$TMP/e.$idx" | uniq -d | sed 's/^/         重复: /' | head -"$SHOW_LIMIT"
      else
        echo "  [C3]  无重复条目      : 唯一 $n_uniq / $n_entries   WARN —— $n_dup 条重复（不阻塞，见 --help）"
        [ "$QUIET" -eq 0 ] && sort "$TMP/e.$idx" | uniq -d | sed 's/^/         重复: /' | head -"$SHOW_LIMIT"
      fi
    fi
  fi

  # --- C4：索引世代（--ref 时启用） ---
  # 只比「双方都有的 modules.*」。单侧存在的一律只告警：modules.order / modules.builtin
  # 这类文件本来就随构建路径变，做成硬门禁会误杀。
  if [ -n "$REF_DIR" ]; then
    local b sum_a sum_b total4=0 diffout=""
    for b in $( { find "$dir"     -maxdepth 1 \( -name 'modules.*' -o -name '*.modules.blocklist' \) -type f -printf '%f\n' 2>/dev/null
                  find "$REF_DIR" -maxdepth 1 \( -name 'modules.*' -o -name '*.modules.blocklist' \) -type f -printf '%f\n' 2>/dev/null; } \
                | sort -u ); do
      if [ ! -f "$dir/$b" ] || [ ! -f "$REF_DIR/$b" ]; then
        c4_only=$((c4_only + 1))
        diffout="$diffout"$'\n'"         仅一侧存在: $b"
        continue
      fi
      total4=$((total4 + 1))
      sum_a=$(md5_of "$dir/$b")
      sum_b=$(md5_of "$REF_DIR/$b")
      if [ "$sum_a" = "$sum_b" ]; then
        c4_same=$((c4_same + 1))
      else
        c4_diff=$((c4_diff + 1))
        diffout="$diffout"$'\n'"         不同: $b  ${sum_a:0:8} ≠ ${sum_b:0:8}"
      fi
    done

    # 一个共同文件都没有 = 目录给错了或索引没生成。空比较过门禁没有意义，判 FAIL。
    if [ "$total4" -eq 0 ]; then
      echo "  [C4]  索引世代一致    : 0 个 modules.* —— 无可比对文件，判 FAIL（--ref）"
      c4_fail=1
    elif [ "$c4_diff" -eq 0 ]; then
      echo "  [C4]  索引世代一致    : $c4_same / $total4 与参考逐字节相同   PASS"
      [ "$c4_only" -gt 0 ] && echo "        ⚠ $c4_only 个索引仅一侧存在（不阻塞）"
    else
      echo "  [C4]  索引世代一致    : $c4_same / $total4   FAIL —— $c4_diff 个与参考不同"
      c4_fail=1
    fi
    [ "$QUIET" -eq 0 ] && [ -n "$diffout" ] && printf '%s\n' "$diffout"
    [ -n "$REF_DIR" ] && echo "        参考: $REF_DIR"
  fi

  local verdict="PASS"
  if [ "$c1_fail" -eq 1 ] || [ "$n_missing" -gt 0 ] || [ "$c3_fail" -eq 1 ] || [ "$c1b_fail" -eq 1 ] || [ "$c4_fail" -eq 1 ]; then
    verdict="FAIL"; FAILED_SETS=$((FAILED_SETS + 1))
  fi
  [ "$c1_fail" -eq 1 ] && FAILED_C1=$((FAILED_C1 + 1))
  [ "$c1b_fail" -eq 1 ] && FAILED_C1B=$((FAILED_C1B + 1))
  [ "$c3_fail" -eq 1 ] && FAILED_C3=$((FAILED_C3 + 1))
  [ "$c4_fail" -eq 1 ] && FAILED_C4=$((FAILED_C4 + 1))
  echo "  => $verdict"
  ROWS+=("$name|$verdict|$n_ko|$n_bad|$n_vm_bad|$n_missing|$n_dup|$( [ -n "$loadpath" ] && [ -f "$loadpath" ] && echo 有 || echo 无)")
}

# ---------- 内核侧（可选） ----------
KERNEL_VERDICT="未指定"
if [ -n "$KERNEL_IMG" ]; then
  if [ ! -f "$KERNEL_IMG" ]; then
    echo "$PROG: 内核映像不存在: $KERNEL_IMG" >&2; exit 2
  fi
  # boot.img 是 header+padding+Image；直接 strings 抓 banner，无需解头
  KBANNER=$(strings -n 8 "$KERNEL_IMG" 2>/dev/null | grep -m1 '^Linux version ' | sed 's/^Linux version //; s/ .*//')
  if [ -z "$KBANNER" ]; then
    KERNEL_VERDICT="FAIL —— 无法从 $KERNEL_IMG 读到 Linux version"
  else
    case "$KBANNER" in
      "$EXPECT_KMI"*) KERNEL_VERDICT="PASS ($KBANNER)" ;;
      *)              KERNEL_VERDICT="FAIL —— 内核是 $KBANNER，与期望 KMI $EXPECT_KMI 不符" ;;
    esac
  fi
fi

# ---------- 表头（只印一次，不在每个集合里重复） ----------
hr
echo "KMI 门禁   期望 module_layout CRC = $EXPECT_CRC   期望 KMI = $EXPECT_KMI"
[ -n "$KERNEL_IMG" ] && echo "           内核 banner 校验 = $KERNEL_VERDICT"
[ -n "$REF_DIR" ]    && echo "           参考构建（C4）= $REF_DIR"
echo "           硬门禁 C1/C2$( [ -n "$REF_DIR" ] && echo "/C4")$( [ "$STRICT_DUP" -eq 1 ] && echo "/C3")$( [ "$STRICT_VMAGIC" -eq 1 ] && echo "/C1b")；其余为告警"

for i in "${!DIRS[@]}"; do
  check_set "${DIRS[$i]}" "$i" "${#DIRS[@]}"
done

# ---------- 汇总 ----------
hr
echo "汇总"
printf '  %-44s %-5s %6s %7s %7s %6s %5s %s\n' 集合 结果 .ko CRC不符 VMAGIC 悬空 重复 清单
for r in "${ROWS[@]}"; do
  IFS='|' read -r n v t b vm m d l <<< "$r"
  # 嵌套目录的集合名可能很长（lib/modules/6.12.69-…），截断保表格可读
  [ ${#n} -gt 44 ] && n="${n:0:21}…${n: -20}"
  printf '  %-44s %-5s %6s %7s %7s %6s %5s %s\n' "$n" "$v" "$t" "$b" "$vm" "$m" "$d" "$l"
done
echo

OVERALL=0
[ "$FAILED_SETS" -gt 0 ] && OVERALL=1
case "$KERNEL_VERDICT" in FAIL*) OVERALL=1 ;; esac

if [ "$OVERALL" -eq 0 ]; then
  echo "门禁结果：PASS —— 模块与内核 KMI 一致，可以出包。"
else
  echo "门禁结果：FAIL —— 拒绝出包。"
  [ "$FAILED_C1" -gt 0 ] && echo "  · C1 $FAILED_C1 个集合存在 module_layout CRC 不符：模块世代与内核不匹配"
  [ "$FAILED_C2" -gt 0 ] && echo "  · C2 $FAILED_C2 个集合存在悬空条目：modules.load 指向不存在的文件"
  [ "$FAILED_C3" -gt 0 ] && echo "  · C3 $FAILED_C3 个集合存在重复条目（--strict-dup）"
  [ "$FAILED_C1B" -gt 0 ] && echo "  · C1b $FAILED_C1B 个集合 vermagic 版本段不符（--strict-vermagic）"
  [ "$FAILED_C4" -gt 0 ]  && echo "  · C4 $FAILED_C4 个集合的 modules.* 索引与参考构建不一致：索引是旧世代生成的"
  [ "$FAILED_C4" -gt 0 ]  && echo "    修法：整目录替换（scripts/maintain/replace_kernel_modules.sh），不要手工改索引"
  case "$KERNEL_VERDICT" in FAIL*) echo "  · 内核 banner 与期望 KMI 不符：内核被换过，但模块没跟着换" ;; esac
fi
exit "$OVERALL"
