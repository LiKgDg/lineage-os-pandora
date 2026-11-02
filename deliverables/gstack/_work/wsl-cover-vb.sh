#!/bin/bash
# 校验 vendor_boot：LOS 的错配模块在 stock 侧是否有同名、CRC 正确的替换件。
# 自包含：缺 ramdisk 就自己解到 $STAGE/vb/。
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_ramdisks

L="$STAGE/vb/los/lib/modules"
S="$STAGE/vb/stock/lib/modules"
EXPECT=0x797f2b3e

echo "########## vendor_boot：LOS 错配模块的可替换率 ##########"
bad=0; cov=0; nocov=""
for f in "$L"/*.ko; do
  b=$(basename "$f")
  c=$(crc_of "$f")
  [ "$c" = "$EXPECT" ] && continue
  bad=$((bad+1))
  if [ -f "$S/$b" ]; then
    [ "$(crc_of "$S/$b")" = "$EXPECT" ] && cov=$((cov+1)) || nocov="$nocov $b(CRC不符)"
  else
    nocov="$nocov $b(无同名)"
  fi
done
echo "LOS 错配: $bad ; 可替换: $cov ; 不可: $((bad-cov))"
[ -n "$nocov" ] && echo "明细:$(echo $nocov | tr ' ' '\n' | head -10 | tr '\n' ' ')"

echo
echo "########## 替换后 modules.load 是否全部可加载（模拟：用 stock 模块集） ##########"
need "$L/modules.load" "LOS vendor_boot modules.load"
miss=0
while read -r m; do
  [ -z "$m" ] && continue
  case "$m" in \#*) continue;; esac
  [ -f "$S/$m" ] || { miss=$((miss+1)); echo "  缺: $m"; }
done < <(awk '{print $1}' "$L/modules.load")
echo "modules.load 中 stock 侧缺失条目: $miss（这些是悬空条目，需从清单删除）"

echo
if [ "$((bad-cov))" -gt 0 ]; then
  echo "FAIL: 有 $((bad-cov)) 个错配模块无法用 stock 同名文件替换"
  exit 1
fi
echo "PASS: 全部 $bad 个错配模块均可由 stock 同名文件替换"
