#!/bin/bash
# 复核 qa-lead 关于 modules.dep / modules.alias 的论断
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_ramdisks
L="$STAGE/vb/los/lib/modules"

echo "########## 1. modules.dep 覆盖率 ##########"
ko=$(find "$L" -maxdepth 1 -name '*.ko' | wc -l)
dep=$(awk -F: 'NF{print $1}' "$L/modules.dep" | sort -u | wc -l)
echo "  .ko 文件: $ko ; modules.dep 有条目: $dep"
echo "  差异: $((ko-dep))"

echo
echo "########## 2. 文件在、dep 无条目的例子（验证判据不成立） ##########"
n=0
for f in "$L"/*.ko; do
  b=$(basename "$f")
  grep -q "^$b:" "$L/modules.dep" || { echo "   $b"; n=$((n+1)); [ $n -ge 6 ] && break; }
done

echo
echo "########## 3. 8 条悬空模块：dep / alias 里的痕迹 ##########"
for m in mem_object qcom_tzmem mi_schedule metis migt miloadtrace mi_mem_epoll mi_mem_limit \
         bcl_soc binder_prio common mca_pbb miwill nvmem_qfprom qcom_cache_allocation quic tls; do
  d=$(grep -c "^$m\.ko:" "$L/modules.dep" 2>/dev/null || true)
  a=$(grep -c "$m" "$L/modules.alias" 2>/dev/null || true)
  printf "  %-24s dep=%s alias=%s\n" "$m.ko" "${d:-0}" "${a:-0}"
done

echo
echo "########## 4. alias 原文（前 8 条命中） ##########"
grep -E "miwill|quic|nvmem_qfprom|qcom_cache_allocation|binder_prio|mca_pbb|mem_object|qcom_tzmem" "$L/modules.alias" | head -8
