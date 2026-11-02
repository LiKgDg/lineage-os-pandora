#!/system/bin/sh
# 确认运行中的 /vendor 到底是哪一份
set -u
OUT="${1:-/data/local/tmp/out2}"
mkdir -p "$OUT"

{
  echo "=== vendor 身份 ==="
  getprop ro.vendor.build.fingerprint
  getprop ro.vendor.build.date
  getprop ro.vendor.build.id
  getprop ro.vendor.build.version.release
  getprop ro.vendor.build.security_patch
  echo
  echo "=== 挂载来源 ==="
  grep -E " /vendor | /vendor_dlkm | /system_dlkm | /odm " /proc/mounts
  echo
  echo "=== /vendor/lib/modules 真实路径 ==="
  ls -ld /vendor/lib/modules
  readlink -f /vendor/lib/modules
  echo
  echo "=== 模块数 ==="
  echo "vendor/lib/modules: $(ls /vendor/lib/modules/*.ko 2>/dev/null | wc -l)"
  echo "vendor_dlkm:        $(ls /vendor_dlkm/lib/modules/*.ko 2>/dev/null | wc -l)"
  echo "system_dlkm ver:    $(find /system_dlkm/lib/modules -name '*.ko' 2>/dev/null | wc -l)"
  echo "system_dlkm flat:   $(find /system_dlkm/flatten -name '*.ko' 2>/dev/null | wc -l)"
} > "$OUT/vendor-id.txt" 2>&1

# 索引文件哈希
md5sum /vendor/lib/modules/modules.load \
       /vendor/lib/modules/modules.alias \
       /vendor/lib/modules/modules.dep \
       /vendor/lib/modules/modules.softdep \
       /vendor/lib/modules/modules.blocklist \
       /system_dlkm/lib/modules/modules.load \
       /system_dlkm/flatten/lib/modules/modules.load \
  > "$OUT/index-md5.txt" 2>&1

# 抽三个模块的哈希（与镜像比）
for m in binder_gki.ko arm_smmu.ko clk-qcom.ko gcc-canoe.ko mi_game.ko; do
  [ -f "/vendor/lib/modules/$m" ] && md5sum "/vendor/lib/modules/$m"
done > "$OUT/sample-ko-md5.txt" 2>&1

# 幽灵条目实测（带 -d 指定目录）
{
  echo "=== modprobe 实测（-d /vendor/lib/modules）==="
  for m in mem_object mi_schedule qcom_tzmem bcl_soc mi_game; do
    r=$(modprobe -d /vendor/lib/modules "$m" 2>&1); rc=$?
    echo "  $m -> rc=$rc ${r}"
  done
} > "$OUT/modprobe-test.txt" 2>&1

echo "done"
