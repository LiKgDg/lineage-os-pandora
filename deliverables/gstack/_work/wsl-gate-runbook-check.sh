#!/bin/bash
# 逐字执行 runbook §S5 的命令，验证它能得到 139 / 366 / 81 并让门禁 PASS
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
G="$W/deliverables/gstack/_work/kmi-gate.sh"
S=/root/work/gstack/qa/sets
K=/root/work/gstack/qa/runbook
rm -rf "$K"; mkdir -p "$K"

# 复原成「已换 .ko、但 modules.load 还是 LOS 原版」的状态
cp -a "$S/fixed-vb" "$K/vendor_ramdisk";      cp -f "$S/los-vb/modules.load"      "$K/vendor_ramdisk/modules.load"
cp -a "$S/fixed-vd" "$K/vendor_dlkm";         cp -f "$S/los-vd/modules.load"      "$K/vendor_dlkm/modules.load"
cp -a "$S/fixed-sd-flat" "$K/system_dlkm_flatten"; cp -f "$S/los-sd-flat/modules.load" "$K/system_dlkm_flatten/modules.load"
echo "起点（应等于 LOS 原版清单条数）:"
for d in vendor_ramdisk vendor_dlkm system_dlkm_flatten; do printf '  %-22s %s\n' "$d" "$(wc -l < "$K/$d/modules.load")"; done
echo

echo "===== 逐字执行 runbook §S5 ====="
cd "$K/vendor_ramdisk"
for m in mem_object qcom_tzmem mi_schedule metis migt miloadtrace mi_mem_epoll mi_mem_limit; do
  sed -i "/^${m}\.ko$/d" modules.load; done
awk '!seen[$0]++' modules.load > .t && mv .t modules.load
echo "vendor_ramdisk/modules.load = $(wc -l < modules.load)   (期望 139)"

cd "$K/vendor_dlkm"
for m in bcl_soc binder_prio common mca_pbb miwill nvmem_qfprom qcom_cache_allocation quic; do
  sed -i "/^${m}\.ko$/d" modules.load; done
awk '!seen[$0]++' modules.load > .t && mv .t modules.load
echo "vendor_dlkm/modules.load   = $(wc -l < modules.load)   (期望 366)"

cd "$K/system_dlkm_flatten" && sed -i '/^tls\.ko$/d' modules.load && echo "system_dlkm_flatten/modules.load = $(wc -l < modules.load)   (期望 81)"
echo

echo "===== 对 S5 结果跑门禁 ====="
bash "$G" -q "$K/vendor_ramdisk" "$K/vendor_dlkm" "$K/system_dlkm_flatten"
echo "### exit=$?"

echo
echo "===== 空白行检查（应全 0）====="
for d in vendor_ramdisk vendor_dlkm system_dlkm_flatten; do
  printf '  %-22s 空行=%s 注释行=%s\n' "$d" "$(grep -c '^$' "$K/$d/modules.load")" "$(grep -c '^#' "$K/$d/modules.load")"
done
