#!/bin/bash
cd /root/android/lineage || exit 9
D=device/xiaomi/pandora/BoardConfig.mk
python3 - <<'PY'
p="device/xiaomi/pandora/BoardConfig.mk"
s=open(p,encoding="utf-8").read()
old = """TARGET_NO_RECOVERY := true
# 不构建 recovery 时 board_config.mk:1060 禁止 BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE
BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE :=
"""
new = """# recovery 仍然要构建（system-only 刷机需要带 fastbootd 的 recovery），
# 因此这里不能设 TARGET_NO_RECOVERY，也不能清空
# BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE（否则 recovery 会带内核，本机 ABL 会拒绝）。
"""
if old in s:
    s = s.replace(old, new, 1)
    open(p,"w",encoding="utf-8").write(s)
    print("PATCHED")
else:
    print("PATTERN NOT FOUND")
PY
export JAVA_HOME=/root/android/lineage/prebuilts/jdk/jdk21/linux-x86
export PATH="$JAVA_HOME/bin:/root/android/lineage/prebuilts/build-tools/linux-x86/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
source build/envsetup.sh >/dev/null 2>&1
lunch lineage_pandora_sysonly-bp4a-userdebug >/dev/null 2>&1
timeout 460 m recoveryimage -j12 >> /root/recovery_build.log 2>&1
echo "rc=$?"
ls -la out/target/product/pandora/recovery.img 2>/dev/null
tail -3 /root/recovery_build.log
