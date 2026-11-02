#!/bin/bash
# 统计两侧 vendor_boot ramdisk 的 vermagic 分布。自包含：缺 ramdisk 就自己解。
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_ramdisks

echo "########## LOS vendor_boot（$(find "$STAGE/vb/los/lib/modules" -name '*.ko' | wc -l) 个 .ko） ##########"
find "$STAGE/vb/los/lib/modules" -name '*.ko' -print0 \
  | xargs -0 -n1 -P8 modinfo -F vermagic 2>/dev/null | sort | uniq -c | sort -rn

echo
echo "########## stock vendor_boot（$(find "$STAGE/vb/stock/lib/modules" -name '*.ko' | wc -l) 个 .ko） ##########"
find "$STAGE/vb/stock/lib/modules" -name '*.ko' -print0 \
  | xargs -0 -n1 -P8 modinfo -F vermagic 2>/dev/null | sort | uniq -c | sort -rn
