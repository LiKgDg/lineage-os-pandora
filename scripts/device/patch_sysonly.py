#!/usr/bin/env python3
"""Apply system-only port patches to the pandora device tree."""

import os
import sys

ROOT = "/root/android/lineage/device/xiaomi/pandora"

# ── 1. minimal device compatibility matrix ───────────────────────────────
os.makedirs(os.path.join(ROOT, "vintf"), exist_ok=True)
with open(os.path.join(ROOT, "vintf", "compatibility_matrix.xml"), "w") as f:
    f.write(
        '<!-- system-only port: 只声明 system-sdk 要求，\n'
        '     不要求 framework 提供 vendor.qti.* / vendor.xiaomi.* 等厂商扩展 HAL。\n'
        '     stock vendor 的原始矩阵见 /root/pandora-stock/vintf/compatibility_matrix.xml -->\n'
        '<compatibility-matrix version="9.0" type="device">\n'
        '    <system-sdk>\n'
        '        <version>36</version>\n'
        '    </system-sdk>\n'
        '</compatibility-matrix>\n'
    )

# ── 2. BoardConfig.mk ────────────────────────────────────────────────────
bc = os.path.join(ROOT, "BoardConfig.mk")
s = open(bc, encoding="utf-8").read()

old_vintf = """# VINTF：允许与 stock vendor 的 manifest 做宽松匹配
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml
DEVICE_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml
"""
new_vintf = """# VINTF：system-only 移植用自己的宽松设备矩阵。
# 不能用 stock 的：它要求 framework 提供 vendor.qti.hardware.sigma_miracast_aidl
# 和 vendor.qti.qccsyshal_aidl，LOS 不构建这两个厂商扩展 HAL。
DEVICE_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml
"""
if old_vintf in s:
    s = s.replace(old_vintf, new_vintf, 1)
elif "DEVICE_MATRIX_FILE := device/xiaomi/pandora/vintf/compatibility_matrix.xml" not in s:
    s += "\n" + new_vintf

sysonly = """
# ── system-only 变体（第一阶段路径 A） ────────────────────────────────
# 只产出 system / system_ext / product，其余分区沿用 stock。
ifeq ($(TARGET_PRODUCT),lineage_pandora_sysonly)
TARGET_NO_KERNEL := true
BOARD_USES_GENERIC_KERNEL_IMAGE := true
TARGET_NO_RECOVERY := true
# stock 侧已有 vendor/odm/vendor_dlkm/system_dlkm，不要重复构建
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE :=
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE :=
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE :=
endif
"""
if "system-only 变体" not in s:
    s += sysonly

open(bc, "w", encoding="utf-8").write(s)

# ── 3. device.mk：sysonly 不应继承厂商 blob ──────────────────────────────
dm = os.path.join(ROOT, "device.mk")
d = open(dm, encoding="utf-8").read()
drop = """# 继承厂商 blob
$(call inherit-product-if-exists, vendor/xiaomi/pandora/pandora-vendor.mk)

"""
if drop in d:
    d = d.replace(drop, "# 厂商 blob 只在完整 ROM（lineage_pandora）里继承；\n"
                       "# system-only 变体的 vendor 由 stock 提供，不能重复打包。\n", 1)
    open(dm, "w", encoding="utf-8").write(d)

print("patched: vintf/compatibility_matrix.xml, BoardConfig.mk, device.mk")
