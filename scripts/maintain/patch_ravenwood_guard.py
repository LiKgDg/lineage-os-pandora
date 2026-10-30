#!/usr/bin/env python3
"""给 build/soong/java/ravenwood.go 的空依赖索引加保护。

背景：ravenwood.go:190 是
    utils := ctx.GetDirectDepsProxyWithTag(ravenwoodUtilsTag)[0]
直接对返回值取 [0]。当 frameworks/base/ravenwood（RavenwoodUtils 模块）不存在时，
返回空切片，索引越界导致 soong bootstrap panic：

    internal error: panic in GenerateBuildActions for module
      "AdServicesSharedLibrariesUnitTestsRavenwood"
    runtime error: index out of range [0] with length 0

本补丁在空切片时跳过该测试模块的构建动作生成，不影响 recoveryimage。
frameworks/base 补齐后可以还原（--revert）。

用法：
    python3 patch_ravenwood_guard.py            # 打补丁
    python3 patch_ravenwood_guard.py --revert   # 还原
"""

import os
import shutil
import sys

P = "/root/twrp/build/soong/java/ravenwood.go"
BAK = P + ".orig"

OLD = "\tutils := ctx.GetDirectDepsProxyWithTag(ravenwoodUtilsTag)[0]\n"

NEW = (
    "\tutilsDeps := ctx.GetDirectDepsProxyWithTag(ravenwoodUtilsTag)\n"
    "\tif len(utilsDeps) == 0 {\n"
    "\t\t// [pandora] RavenwoodUtils 依赖缺失（frameworks/base/ravenwood 未同步）。\n"
    "\t\t// 原代码直接取 [0] 会 panic，这里跳过该测试模块的构建动作生成。\n"
    "\t\t// 补齐 frameworks/base 后可还原本补丁。\n"
    "\t\treturn\n"
    "\t}\n"
    "\tutils := utilsDeps[0]\n"
)

MARK = "[pandora] RavenwoodUtils"


def main():
    revert = "--revert" in sys.argv

    if not os.path.isfile(P):
        print(f"找不到 {P}")
        return 1

    src = open(P, encoding="utf-8").read()

    if revert:
        if not os.path.isfile(BAK):
            print("没有备份文件，无法还原")
            return 1
        shutil.copy2(BAK, P)
        print("已还原 ravenwood.go")
        return 0

    if MARK in src:
        print("已打过补丁，跳过")
        return 0

    if OLD not in src:
        print("未找到目标行，源码可能已变化")
        return 1

    if not os.path.isfile(BAK):
        shutil.copy2(P, BAK)
        print(f"已备份到 {BAK}")

    open(P, "w", encoding="utf-8").write(src.replace(OLD, NEW, 1))
    print("补丁已应用")
    return 0


if __name__ == "__main__":
    sys.exit(main())
