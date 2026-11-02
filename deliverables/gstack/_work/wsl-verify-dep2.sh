#!/bin/bash
# 在 vendor_dlkm 分区里复核 8 条悬空的 dep/alias 痕迹
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_stock_dlkm_mount vendor_dlkm
M="$STAGE/mnt/stock_vendor_dlkm/lib/modules"

mkdir -p "$STAGE/mnt/los_vd"
mountpoint -q "$STAGE/mnt/los_vd" || mount -o loop,ro "$IMGS/vendor_dlkm.img" "$STAGE/mnt/los_vd" || exit 9
L="$STAGE/mnt/los_vd/lib/modules"

echo "########## LOS vendor_dlkm 的 dep/alias 覆盖 ##########"
ko=$(find "$L" -maxdepth 1 -name '*.ko' | wc -l)
dep=$(awk -F: 'NF{print $1}' "$L/modules.dep" | sort -u | wc -l)
echo "  .ko=$ko  dep 条目=$dep  差=$((ko-dep))"

echo
echo "########## 8 条悬空在 LOS vendor_dlkm 里的痕迹 ##########"
for m in bcl_soc binder_prio common mca_pbb miwill nvmem_qfprom qcom_cache_allocation quic; do
  d=$(grep -c "^$m\.ko:" "$L/modules.dep" 2>/dev/null || true)
  a=$(grep -c "\b$m\b" "$L/modules.alias" 2>/dev/null || true)
  f=$([ -f "$L/$m.ko" ] && echo Y || echo -)
  printf "  %-24s 文件=%s dep=%s alias=%s\n" "$m.ko" "$f" "${d:-0}" "${a:-0}"
done

echo
echo "########## alias 原文 ##########"
grep -E "miwill|quic|nvmem_qfprom|qcom_cache_allocation|binder_prio|mca_pbb" "$L/modules.alias" 2>/dev/null | head -10

umount "$STAGE/mnt/los_vd" 2>/dev/null
