#!/usr/bin/env python3
"""生成 vendor/xiaomi/pandora 的 proprietary-files.txt。

边界（依据 sm8850-common 权威基准 vendor+odm 占 93%）：
- vendor + odm：blobs 主体，取「PixelOS 有、sm8850-common 清单未覆盖」的增量
- system_ext + product：只取专有命名组件（Qti/QCC/Pandora 等）
- 排除：
  * 指向 toybox_vendor/toolbox 的符号链接（开源 toybox 命令，AOSP 可构建）
  * 杂物扩展名：.vim/.nanorc/.txt/.png/.webp/.ogg/.vdex/.odex/fonts/oat 等
  * toybox_vendor/toolbox 二进制本身

来源：PixelOS_pandora-17.0-20261102（A17、pandora 同机型、已实机验证）
"""
import os
from collections import Counter

# 路径可从环境变量覆盖，默认指向标准 LOS 树位置
M = os.environ.get("SM8850_COMMON_MANIFEST",
                   "/root/los24/device/xiaomi/sm8850-common/proprietary-files.txt")
PX = "/root/los24/vendor/xiaomi/pandora/proprietary"
OUT = "/root/los24/device/xiaomi/pandora/proprietary-files.txt"

covered = set()
for line in open(M, encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#"):
        covered.add(line.lstrip("-").split(":")[0])

EXCLUDE_EXT = {".vim", ".nanorc", ".vdex", ".odex", ".art", ".markdown",
               ".fsv_meta", ".txt", ".png", ".webp", ".ogg", ".jpg", ".jpeg",
               ".gif", ".mp3", ".wav", ".apk.sig"}
EXCLUDE_DIRS = {"lost+found", "oat", "fonts"}
# vintf manifest/compatibility matrix 不是 blob，应由 device tree 的
# DEVICE_MANIFEST_FILE / ODM_MANIFEST_FILES 声明（kati 会拒绝 PRODUCT_COPY_FILES 里的 vintf）
EXCLUDE_PATH_SUBSTR = "vintf"
# 开源 toybox 相关（AOSP 可构建，非专有 blob）
EXCLUDE_NAMES = {"toybox_vendor", "toolbox", "toybox", "toolbox_vendor"}

def _exclude_by_ext(f):
    """按扩展名排除，兼容多段扩展名（如 .apk.sig）。"""
    low = f.lower()
    for ext in EXCLUDE_EXT:
        if low.endswith(ext):
            return True
    return False


def is_excluded(full, f):
    if f in EXCLUDE_NAMES:
        return True
    # 指向 toybox/toolbox 的符号链接
    if os.path.islink(full):
        target = os.readlink(full)
        if target in EXCLUDE_NAMES:
            return True
    return False

def walk(part):
    pd = os.path.join(PX, part)
    if not os.path.isdir(pd):
        return
    for root, dirs, files in os.walk(pd):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, pd)
            ext = os.path.splitext(f)[1].lower()
            if _exclude_by_ext(f):
                continue
            if EXCLUDE_PATH_SUBSTR in rel.lower():
                continue
            if is_excluded(full, f):
                continue
            key = f"{part}/{rel}"
            if key not in covered:
                yield key

increment = sorted(walk("vendor")) + sorted(walk("odm"))

def is_proprietary_name(k):
    base = os.path.basename(k).lower()
    markers = ["qti", "qcc", "pandora", "carrierconfig", "ifaaservice",
               "cnapp", "cneapp", "soter", "trustzone", "timezone", "time",
               "paranoid", "pixelos", "dpm", "qcril", "ril", "diag", "nfc",
               "uwb", "gps", "gnss", "ims", "dolby", "xiaomi", "mi_"]
    return any(m in base for m in markers)

for part in ["system_ext", "product"]:
    pd = os.path.join(PX, part)
    if not os.path.isdir(pd):
        continue
    for root, dirs, files in os.walk(pd):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            full = os.path.join(root, f)
            rel = os.path.relpath(full, pd)
            if _exclude_by_ext(f) or is_excluded(full, f):
                continue
            key = f"{part}/{rel}"
            if key not in covered and is_proprietary_name(key):
                increment.append(key)

increment = sorted(set(increment))
with open(OUT, "w") as fo:
    fo.write("# pandora (Xiaomi 17 Pro) 专属 blobs（相对 sm8850-common 的增量）\n")
    fo.write("# 来源：PixelOS_pandora-17.0-20261102（A17、pandora 同机型、已实机验证）\n")
    fo.write("# 生成：scripts/device/gen_pandora_manifest.py\n")
    fo.write("# 边界：vendor+odm 全量增量；system_ext+product 只取专有组件；排除 toybox/开源命令\n\n")
    fo.write("\n".join(increment) + "\n")

parts = Counter(k.split("/")[0] for k in increment)
print(f"增量条目: {len(increment)}")
print(f"分区分布: {dict(parts)}")
