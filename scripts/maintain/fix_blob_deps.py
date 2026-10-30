#!/usr/bin/env python3
"""移除 Xiaomi blob 包里 libwfdcommonutils 对 libdng_sdk 的虚假依赖。

背景：
  vendor/xiaomi/sm8850-common/Android.bp 中 libwfdcommonutils（system_ext_specific）
  的 shared_libs 列了 libdng_sdk，该列表是从 .so 的 DT_NEEDED 全量导出的。
  system_ext 模块依赖 vendor_available 库时会解析到 vendor 变体，而
  libdng_sdk(vendor) -> xmp_toolkit_sdk(vendor) -> zuid_md5(vendor) 整条链
  在 AOSP 里只有 host/sdk 变体，必然失败。

  在提供方逐个补 vendor_available 会无限级联（已验证：skcms -> hwy -> xmp -> zuid_md5），
  因此在消费方（Xiaomi prebuilt）摘掉这条不存在的依赖。
"""
import re
import sys

BP = "/root/los24/vendor/xiaomi/sm8850-common/Android.bp"
TARGET_MODULE = "libwfdcommonutils"
DEP = "libdng_sdk"


def find_module_block(text, name):
    """返回 (start, end) —— 包含该 name 的 cc_* 模块块的行区间。"""
    lines = text.split("\n")
    idx = None
    for i, ln in enumerate(lines):
        if re.search(r'name:\s*"%s"' % re.escape(name), ln):
            idx = i
            break
    if idx is None:
        return None
    start = idx
    while start > 0 and lines[start].strip() != "" and not re.match(r"^[a-z_]+\s*\{", lines[start]):
        start -= 1
    depth = 0
    end = start
    for j in range(start, len(lines)):
        depth += lines[j].count("{") - lines[j].count("}")
        if depth == 0 and j > start:
            end = j
            break
    return start, end


def main():
    text = open(BP, encoding="utf-8").read()
    span = find_module_block(text, TARGET_MODULE)
    if not span:
        print("FAIL: 找不到模块 %s" % TARGET_MODULE)
        return 1
    start, end = span
    lines = text.split("\n")

    hit = [i for i in range(start, end + 1) if re.search(r'"%s",' % re.escape(DEP), lines[i])]
    if not hit:
        print("SKIP: %s 内没有 %s 依赖" % (TARGET_MODULE, DEP))
        return 0
    if len(hit) != 1:
        print("FAIL: 期望 1 处，实际 %d 处" % len(hit))
        return 1

    i = hit[0]
    print("命中 第 %d 行: %s" % (i + 1, lines[i].strip()))
    lines[i] = lines[i].replace(
        '"%s",' % DEP,
        '// "%s",  // pandora: DT_NEEDED 导出项，AOSP 侧无 vendor 变体，摘除以避免级联报错' % DEP,
    )
    open(BP, "w", encoding="utf-8").write("\n".join(lines))
    print("PATCHED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
