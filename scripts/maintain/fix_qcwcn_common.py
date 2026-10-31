#!/usr/bin/env python3
"""修复 lib_driver_cmd_qcwcn 的 drv/bss 重复符号。

背景：
  hardware/qcom-caf/wlan/qcwcn/wpa_supplicant_8_lib/driver_cmd_nl80211_common.h
  第 57-58 行在头文件里写了不带 extern 的全局定义：

      struct wpa_driver_nl80211_data *drv;
      struct i802_bss *bss;

  该头被 6 个 .c 包含，每个目标文件都产出一个强符号。现代编译器默认
  -fno-common，链接时报 duplicate symbol: drv / bss。

做法：给该模块加 -fcommon，恢复「暂定定义按 COMMON 符号合并」的旧语义。
不改任何源码，语义不变。

用法:
  fix_qcwcn_common.py [--revert]
"""
import os
import sys

BP = "/root/los24/hardware/qcom-caf/wlan/qcwcn/wpa_supplicant_8_lib/Android.bp"
ANCHOR = '''    cflags: [
        "-DCONFIG_ANDROID_LOG",
        "-DCONFIG_P2P",'''
PATCHED = '''    cflags: [
        "-DCONFIG_ANDROID_LOG",
        "-DCONFIG_P2P",
        // pandora-fix: driver_cmd_nl80211_common.h 在头文件里定义 drv/bss
        // 全局变量，被 6 个 .c 包含，-fno-common 下链接报 duplicate symbol
        "-fcommon",'''


def main():
    text = open(BP, encoding="utf-8").read()
    revert = "--revert" in sys.argv

    if revert:
        if PATCHED in text:
            open(BP, "w", encoding="utf-8").write(text.replace(PATCHED, ANCHOR, 1))
            print("REVERTED")
        else:
            print("SKIP: not patched")
        return 0

    if PATCHED in text:
        print("SKIP: already patched")
        return 0
    if ANCHOR not in text:
        print("FAIL: anchor not found")
        return 1

    open(BP, "w", encoding="utf-8").write(text.replace(ANCHOR, PATCHED, 1))
    print("PATCHED %s" % BP)
    return 0


if __name__ == "__main__":
    sys.exit(main())
