#!/usr/bin/env python3
"""让 alsd 能找到 citsensors AIDL 头。

背景：
  device/xiaomi/sm8850-common/interfaces/citsensors 里的 aidl_interface
  会生成 vendor.xiaomi.sensor.citsensorservice-V1-ndk（含导出头）。
  但 vendor/xiaomi/sm8850-common/Android.bp 里有一个同名 prebuilt
  且 prefer: true，把生成版盖掉了；prebuilt 只打包 .so，不导出头，
  于是 alsd.cpp 的 #include <aidl/vendor/xiaomi/sensor/citsensorservice/
  ICitSensorService.h> 找不到。

做法：把该 prebuilt 的 prefer 改为 false，让 aidl_interface 生成的模块生效。

用法:
  fix_citsensor_prebuilt.py [--revert]
"""
import re
import sys

BP = "/root/los24/vendor/xiaomi/sm8850-common/Android.bp"
MODULE = "vendor.xiaomi.sensor.citsensorservice-V1-ndk"


def find_block(lines, name):
    for i, ln in enumerate(lines):
        if re.search(r'name:\s*"%s"' % re.escape(name), ln):
            start = i
            while start > 0 and not re.match(r"^[a-z_]+\s*\{", lines[start]):
                start -= 1
            depth = 0
            for j in range(start, len(lines)):
                depth += lines[j].count("{") - lines[j].count("}")
                if depth == 0 and j > start:
                    return start, j
    return None


def main():
    lines = open(BP, encoding="utf-8").read().split("\n")
    span = find_block(lines, MODULE)
    if not span:
        print("FAIL: 找不到模块 %s" % MODULE)
        return 1
    start, end = span

    revert = "--revert" in sys.argv
    want = "    prefer: true," if revert else "    prefer: false,"
    other = "    prefer: false," if revert else "    prefer: true,"

    for i in range(start, end + 1):
        if lines[i].strip() == other.strip():
            lines[i] = want
            open(BP, "w", encoding="utf-8").write("\n".join(lines))
            print("%s %s 行%d: %s -> %s" % (
                "REVERTED" if revert else "PATCHED", MODULE, i + 1, other.strip(), want.strip()))
            return 0
    print("SKIP: 模块内未找到 %s" % other.strip())
    return 0


if __name__ == "__main__":
    sys.exit(main())
