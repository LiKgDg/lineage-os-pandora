#!/usr/bin/env python3
"""修复 libwfdcommonutils 的 check_elf_file 失败。

背景：
  vendor/xiaomi/sm8850-common 的 prebuilt libwfdcommonutils.so 在 DT_NEEDED
  里依赖 libdng_sdk.so，但该库在 AOSP 侧只有 SDK 变体、没有 vendor 变体
  （早期为了绕开 vendor 变体级联，已把这条依赖从 shared_libs 摘掉）。
  于是 check_elf_file 报：

      error: DT_NEEDED "libdng_sdk.so" is not specified in shared_libs.

  正确做法不是伪造依赖，而是对这类「依赖无法在 AOSP 侧提供」的 prebuilt
  关闭 ELF 校验。

用法:
  fix_wfd_elfcheck.py [--revert]
"""
import re
import sys

BP = "/root/los24/vendor/xiaomi/sm8850-common/Android.bp"
MODULE = "libwfdcommonutils"
MARK = "    // pandora-fix: libdng_sdk 无 vendor 变体，DT_NEEDED 校验无法满足\n    check_elf_files: false,\n"


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
    text = open(BP, encoding="utf-8").read()
    lines = text.split("\n")
    span = find_block(lines, MODULE)
    if not span:
        print("FAIL: 找不到模块 %s" % MODULE)
        return 1
    start, end = span

    revert = "--revert" in sys.argv

    if revert:
        if MARK not in text:
            print("SKIP: not patched")
            return 0
        open(BP, "w", encoding="utf-8").write(text.replace(MARK, "", 1))
        print("REVERTED")
        return 0

    if MARK in text:
        print("SKIP: already patched")
        return 0

    # 插到模块块结束前（最后一个 } 之前）
    indent = "    "
    lines[end:end] = [
        indent + "// pandora-fix: libdng_sdk 无 vendor 变体，DT_NEEDED 校验无法满足",
        indent + "check_elf_files: false,",
    ]
    open(BP, "w", encoding="utf-8").write("\n".join(lines))
    print("PATCHED %s (模块块 %d-%d)" % (MODULE, start + 1, end + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
