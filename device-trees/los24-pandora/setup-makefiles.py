#!/usr/bin/env python3
"""从 proprietary-files.txt 生成 vendor/xiaomi/pandora 的 Android.bp 与 pandora-vendor.mk。

与 sm8850-common 的区别：pandora 的 blobs 由 scripts/device/gen_pandora_manifest.py
从 PixelOS 包预先生成，本脚本只做「清单 → 构建文件」这一步。

关键：.apk 不能走 PRODUCT_COPY_FILES（kati 会拒绝），必须生成
android_app_import 模块 + PRODUCT_PACKAGES 引用——这是 extract-utils 的标准行为。
"""
import os

DEVICE_DIR = os.path.dirname(os.path.abspath(__file__))
MANIFEST = os.path.join(DEVICE_DIR, "proprietary-files.txt")
VENDOR_DIR = "/root/los24/vendor/xiaomi/pandora"
VENDOR_PREFIX = "vendor/xiaomi/pandora/proprietary"

# 分区 -> (COPY_FILES 目标变量, android_app_import 的 *_specific 字段)
PART_MAP = {
    "vendor": ("TARGET_COPY_OUT_VENDOR", "soc_specific"),
    "odm": ("TARGET_COPY_OUT_ODM", "device_specific"),
    "product": ("TARGET_COPY_OUT_PRODUCT", "product_specific"),
    "system_ext": ("TARGET_COPY_OUT_SYSTEM_EXT", "system_ext_specific"),
    "system": ("TARGET_COPY_OUT_SYSTEM", "system_ext_specific"),
}

copy_files = []
apks = []  # (模块名, apk相对路径, specific字段)

for line in open(MANIFEST, encoding="utf-8"):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    src = s.lstrip("-").split(":")[0]
    part, _, rel = src.partition("/")
    if part not in PART_MAP:
        continue
    out_var, specific = PART_MAP[part]
    if rel.lower().endswith(".apk"):
        # apk 走 android_app_import
        name = os.path.basename(rel)[:-4]  # 去 .apk
        apks.append((name, src, specific))
    else:
        copy_files.append(f"    {VENDOR_PREFIX}/{src}:$({out_var})/{rel} \\")

# ---- 生成 pandora-vendor.mk ----
mk = []
mk.append("#\n# Automatically generated file. DO NOT MODIFY\n#\n")
mk.append("# 由 device/xiaomi/pandora/setup-makefiles.py 生成\n")
mk.append("# 来源：PixelOS_pandora-17.0-20261102（pandora 同机型、已实机验证）\n#\n\n")
mk.append("PRODUCT_SOONG_NAMESPACES += \\\n    vendor/xiaomi/pandora\n\n")
if apks:
    mk.append("# 预装 apk（android_app_import 模块，见 Android.bp）\n")
    mk.append("PRODUCT_PACKAGES += \\\n")
    for name, _, _ in apks:
        mk.append(f"    {name} \\\n")
    mk.append("\n")
mk.append("PRODUCT_COPY_FILES += \\\n")
mk.append("\n".join(copy_files) + "\n")
with open(os.path.join(VENDOR_DIR, "pandora-vendor.mk"), "w") as fo:
    fo.write("".join(mk))

# ---- 生成 Android.bp（soong_namespace + android_app_import 模块）----
bp = []
bp.append("//\n// Automatically generated file. DO NOT MODIFY\n//\n//\n")
bp.append("soong_namespace {\n")
bp.append("    imports: [\n")
bp.append('        "device/xiaomi/pandora",\n')
bp.append('        "device/xiaomi/sm8850-common",\n')
bp.append('        "hardware/qcom-caf/sm8850",\n')
bp.append('        "hardware/qcom-caf/wlan",\n')
bp.append('        "hardware/xiaomi",\n')
bp.append("    ],\n")
bp.append("}\n\n")
for name, src, specific in apks:
    bp.append("android_app_import {\n")
    bp.append(f'    name: "{name}",\n')
    bp.append('    owner: "xiaomi",\n')
    bp.append(f'    apk: "proprietary/{src}",\n')
    bp.append('    certificate: "platform",\n')
    bp.append("    dex_preopt: {\n")
    bp.append("        enabled: false,\n")
    bp.append("    },\n")
    bp.append(f"    {specific}: true,\n")
    bp.append("}\n\n")
with open(os.path.join(VENDOR_DIR, "Android.bp"), "w") as fo:
    fo.write("".join(bp))

print(f"生成 pandora-vendor.mk：{len(copy_files)} COPY_FILES + {len(apks)} PRODUCT_PACKAGES")
print(f"生成 Android.bp：{len(apks)} 个 android_app_import 模块")
