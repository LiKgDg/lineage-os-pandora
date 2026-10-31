#!/usr/bin/env python3
"""让 build-manifest.xml 的生成在 .repo 不可用时降级，而不是硬失败。

背景：vendor/lineage/build/tasks/build-manifest_xml.mk 的 recipe 直接调用
  python3 .repo/repo/repo manifest -o - -r
当 .repo 位于独立虚拟磁盘且未挂载时，这一步会让整个 mka bacon 失败。
个人构建用不到这份 manifest，因此改为：缺失时写占位 XML 并在 stderr 警告。

用法:
  patch_manifest_stub.py          应用
  patch_manifest_stub.py --revert 还原
"""
import os
import re
import sys

MK = "/root/los24/vendor/lineage/build/tasks/build-manifest_xml.mk"

RECIPE_ORIG = (
    "\tREPO_TRACE=0 python3 .repo/repo/repo manifest -o - -r | "
    'grep -Ev "proprietary_$(MANIFEST_EXCLUDES)" > $@\n'
)

RECIPE_NEW = (
    "\t@if [ -x .repo/repo/repo ] && [ -d .repo/project-objects ]; then \\\n"
    "\t    REPO_TRACE=0 python3 .repo/repo/repo manifest -o - -r | "
    'grep -Ev "proprietary_$(MANIFEST_EXCLUDES)" > $@; \\\n'
    "\telse \\\n"
    '\t    echo "WARNING: .repo unavailable, writing stub build-manifest.xml" >&2; \\\n'
    "\t    printf '%s\\n' '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' "
    "'<manifest>' '<notice>.repo unavailable at build time; manifest omitted</notice>' "
    "'</manifest>' > $@; \\\n"
    "\tfi\n"
)


def main():
    text = open(MK, encoding="utf-8").read()
    revert = "--revert" in sys.argv

    if revert:
        if RECIPE_NEW in text:
            open(MK, "w", encoding="utf-8").write(text.replace(RECIPE_NEW, RECIPE_ORIG, 1))
            print("REVERTED")
        else:
            print("SKIP: not in patched state")
        return 0

    if RECIPE_NEW in text:
        print("SKIP: already patched")
        return 0
    if RECIPE_ORIG not in text:
        print("FAIL: recipe not found, file layout changed")
        return 1

    open(MK, "w", encoding="utf-8").write(text.replace(RECIPE_ORIG, RECIPE_NEW, 1))
    print("PATCHED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
