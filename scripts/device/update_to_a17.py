#!/usr/bin/env python3
"""把设备树中 A16（OS3.0.318.0 / 6.12.23）配置更新为 A17（OS4.0.5.0 / 6.12.69）。

修改项：
  1. BoardConfig.mk  system_dlkm 模块路径的内核版本目录
  2. lineage_pandora.mk  BUILD_FINGERPRINT
  3. configs/properties/odm.prop  来源注释
同时作用于项目副本与 WSL 构建树。
"""
import os
import sys

OLD_KVER = "6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k"
NEW_KVER = "6.12.69-android16-6-g43b5ab7e247d-abogki561813157-4k"
OLD_FP = "Xiaomi/pandora/pandora:16/BP2A.250605.031.A3/OS3.0.318.0.WBLCNXM:user/release-keys"
NEW_FP = "Xiaomi/pandora/pandora:17/CP2A.260605.016/OS4.0.5.0.XBLCNXM:user/release-keys"

ROOTS = [
    "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/device-trees/los24-pandora",
    "/root/los24/device/xiaomi/pandora",
]

FILES = ["BoardConfig.mk", "lineage_pandora.mk", "configs/properties/odm.prop"]

COMMENT_OLD = "# 全部取自 stock（OS3.0.318.0.WBLCNXM）实测："
COMMENT_NEW = "# 全部取自 stock（OS4.0.5.0.XBLCNXM）实测："


def patch(path, revert=False):
    if not os.path.exists(path):
        return 0
    txt = open(path, encoding="utf-8").read()
    orig = txt
    if revert:
        txt = txt.replace(NEW_KVER, OLD_KVER).replace(NEW_FP, OLD_FP)
        txt = txt.replace(COMMENT_NEW, COMMENT_OLD)
    else:
        txt = txt.replace(OLD_KVER, NEW_KVER).replace(OLD_FP, NEW_FP)
        txt = txt.replace(COMMENT_OLD, COMMENT_NEW)
    if txt != orig:
        open(path, "w", encoding="utf-8").write(txt)
        return 1
    return 0


def main():
    revert = "--revert" in sys.argv
    n = 0
    for root in ROOTS:
        for f in FILES:
            p = os.path.join(root, f)
            if patch(p, revert):
                print("  %s %s" % ("还原" if revert else "更新", p))
                n += 1
    print("共修改 %d 个文件" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
