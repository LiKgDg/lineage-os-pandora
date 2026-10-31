#!/usr/bin/env python3
"""修复 bootable/recovery/volume_manager/PublicVolume.cpp 缺少 <algorithm>。

背景：第 65 行使用 std::replace，该符号定义在 <algorithm>。
新版 libc++ 移除了传递包含，导致：

    PublicVolume.cpp:65:18: error: no member named 'replace' in namespace 'std'

这是上游 LineageOS 的疏漏，与机型树无关。

用法:
  fix_recovery_algorithm.py          应用
  fix_recovery_algorithm.py --revert 还原
"""
import sys

SRC = "/root/los24/bootable/recovery/volume_manager/PublicVolume.cpp"

ANCHOR = "#include <android-base/logging.h>\n"
PATCHED = "#include <algorithm>\n\n" + ANCHOR


def main():
    text = open(SRC, encoding="utf-8").read()
    revert = "--revert" in sys.argv

    if revert:
        if PATCHED in text:
            open(SRC, "w", encoding="utf-8").write(text.replace(PATCHED, ANCHOR, 1))
            print("REVERTED")
        else:
            print("SKIP: not in patched state")
        return 0

    if PATCHED in text:
        print("SKIP: already patched")
        return 0
    if ANCHOR not in text:
        print("FAIL: anchor not found, file layout changed")
        return 1

    open(SRC, "w", encoding="utf-8").write(text.replace(ANCHOR, PATCHED, 1))
    print("PATCHED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
