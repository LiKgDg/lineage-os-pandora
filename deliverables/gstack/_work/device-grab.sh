#!/system/bin/sh
# PixelOS 实机取证：一次跑完，只读，不改任何分区
# 用法：adb push 到 /data/local/tmp/ && adb shell su -c "sh /data/local/tmp/grab.sh /data/local/tmp/out"
set -u
OUT="${1:-/data/local/tmp/out}"
mkdir -p "$OUT" || exit 9

echo "== 基本身份 ==" > "$OUT/id.txt"
{
  echo "uname: $(uname -a)"
  echo "uptime: $(cat /proc/uptime)"
  echo "boot_completed: $(getprop sys.boot_completed)"
  echo "custom_version: $(getprop ro.custom.version)"
  echo "build_flavor: $(getprop ro.build.flavor)"
  echo "vendor_fp: $(getprop ro.vendor.build.fingerprint)"
  echo "system_fp: $(getprop ro.system.build.fingerprint)"
  echo "boottime_ms: $(cat /proc/stat | grep btime)"
} >> "$OUT/id.txt" 2>&1

cat /proc/cmdline > "$OUT/cmdline.txt" 2>&1
cat /proc/version  > "$OUT/kernel-version.txt" 2>&1

# 模块清单（运行时真相）
cat /proc/modules > "$OUT/proc-modules.txt" 2>&1
lsmod > "$OUT/lsmod.txt" 2>&1
ls /sys/module > "$OUT/sys-module.txt" 2>&1

# 三处分区的实际内容
ls -la /vendor/lib/modules/      > "$OUT/vendor-lib-modules.txt" 2>&1
ls -la /vendor_dlkm/lib/modules/ > "$OUT/vendor-dlkm-modules.txt" 2>&1
ls -laR /system_dlkm/lib/modules/ > "$OUT/system-dlkm-modules.txt" 2>&1

# 清单与索引
for f in /vendor/lib/modules/modules.load /vendor/lib/modules/modules.load.recovery \
         /vendor_dlkm/lib/modules/modules.load /system_dlkm/lib/modules/modules.load; do
  [ -f "$f" ] && cp "$f" "$OUT/$(echo "$f" | tr '/' '_')" 2>/dev/null
done
[ -f /vendor/etc/fstab.qcom ] && cp /vendor/etc/fstab.qcom "$OUT/fstab.qcom"

# dmesg（关键：模块加载与 probe 的真实日志）
dmesg > "$OUT/dmesg.txt" 2>&1
dmesg | grep -iE "disagrees about version|module_layout|Unknown symbol|failed to load|vermagic" \
  > "$OUT/dmesg-module-errors.txt" 2>&1

# pstore（本次启动不该有，但确认通道）
ls -la /sys/fs/pstore/ > "$OUT/pstore.txt" 2>&1

# 关键属性全量
getprop > "$OUT/getprop-all.txt" 2>&1

# 分区与挂载
cat /proc/mounts > "$OUT/mounts.txt" 2>&1
df -h /data /metadata 2>/dev/null > "$OUT/df.txt"

echo "done -> $OUT"
ls -la "$OUT" | tail -20
