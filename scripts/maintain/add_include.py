#!/usr/bin/env python3
"""给 C++ 源文件补标准头文件（新版 libc++ 取消传递包含后的常见修复）。

用法:
    add_include.py <相对源码根的文件路径> <头文件1>[,<头文件2>...] [--revert]

示例:
    add_include.py vendor/qcom/opensource/vibrator/aidl/VibratorSelector/VibratorSelector.cpp memory,vector

行为:
    1. 若文件已包含目标头文件则跳过（幂等）
    2. 插入到「第一个 include 区块」里最后一条 #include <...> 之后
    3. 插入行带统一标记注释，便于 --revert 精确撤销
"""
import os
import re
import sys

ROOT = "/root/los24"
MARK = "// pandora-fix: missing std header"


def target_lines(headers):
    # 注意：写回时用 "\n".join，因此这里不能再带换行符
    return ["#include <%s> %s" % (h, MARK) for h in headers]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2

    rel = sys.argv[1]
    headers = [h.strip() for h in sys.argv[2].split(",") if h.strip()]
    revert = "--revert" in sys.argv
    path = os.path.join(ROOT, rel)

    if not os.path.isfile(path):
        print("FAIL: not found %s" % path)
        return 1

    lines = open(path, encoding="utf-8").read().split("\n")
    # 保留行尾结构：split 后每行不含 \n，写回时用 "\n".join
    new_lines = target_lines(headers)

    if revert:
        kept = [ln for ln in lines if MARK not in ln]
        if len(kept) == len(lines):
            print("SKIP: nothing to revert")
            return 0
        open(path, "w", encoding="utf-8").write("\n".join(kept))
        print("REVERTED: removed %d line(s)" % (len(lines) - len(kept)))
        return 0

    # 幂等检查
    present = [h for h in headers if re.search(r"#include <%s>" % re.escape(h), "\n".join(lines))]
    todo = [h for h in headers if h not in present]
    if not todo:
        print("SKIP: already includes %s" % ", ".join(headers))
        return 0

    # 在第一个 include 区块内找最后一条系统 include
    last_sys = None
    seen_any = False
    for i, ln in enumerate(lines[:300]):
        if re.match(r"\s*#include\s+<", ln):
            last_sys = i
            seen_any = True
        elif re.match(r'\s*#include\s+"', ln):
            seen_any = True
    if last_sys is None:
        print("FAIL: no system include block found in %s" % rel)
        return 1

    ins = target_lines(todo)
    lines[last_sys + 1:last_sys + 1] = ins
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    print("PATCHED %s: +%s (after line %d)" % (rel, ", ".join(todo), last_sys + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
