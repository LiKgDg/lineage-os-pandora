#!/usr/bin/env python3
"""从 proprietary-files.txt 生成 vendor/xiaomi/pandora/pandora-vendor.mk。

与 sm8850-common 不同：pandora 的 blobs 由 scripts/device/gen_pandora_manifest.py
从 PixelOS 包预先生成（见仓库 docs），本脚本只做「清单 → makefile」这一步，
不负责从设备提取（extract 阶段已离线完成）。
"""
import os

MANIFEST = os.path.join(os.path.dirname(__file__), "proprietary-files.txt")
OUT = "/root/los24/vendor/xiaomi/pandora/pandora-vendor.mk"
VENDOR_PREFIX = "vendor/xiaomi/pandora/proprietary"

PART_MAP = {
    "vendor": "TARGET_COPY_OUT_VENDOR",
    "odm": "TARGET_COPY_OUT_ODM",
    "product": "TARGET_COPY_OUT_PRODUCT",
    "system_ext": "TARGET_COPY_OUT_SYSTEM_EXT",
    "system": "TARGET_COPY_OUT_SYSTEM",
}

lines = []
for line in open(MANIFEST, encoding="utf-8"):
    s = line.strip()
    if not s or s.startswith("#"):
        continue
    # 格式：分区/路径 或 源:目标（pandora 清单只用前者）
    src = s.lstrip("-").split(":")[0]
    part, _, rel = src.partition("/")
    out_var = PART_MAP.get(part)
    if not out_var:
        continue
    lines.append(
        f"    {VENDOR_PREFIX}/{src}:$({out_var})/{rel} \\"
    )

body = "\n".join(lines)

with open(OUT, "w") as fo:
    fo.write("#\n# Automatically generated file. DO NOT MODIFY\n#\n")
    fo.write("# 由 device/xiaomi/pandora/setup-makefiles.py 生成\n")
    fo.write("# 来源：PixelOS_pandora-17.0-20261102（pandora 同机型、已实机验证）\n#\n\n")
    fo.write("PRODUCT_SOONG_NAMESPACES += \\\n    vendor/xiaomi/pandora\n\n")
    fo.write("PRODUCT_COPY_FILES += \\\n")
    fo.write(body + "\n")

print(f"生成 {OUT}：{len(lines)} 个 COPY_FILES 条目")
