#!/usr/bin/env python3
"""批量开关 Android.bp 中指定模块的 vendor_available。

用法:
  toggle_vendor.py off external/libjxl/Android.bp:libjxl external/dng_sdk/Android.bp:libdng_sdk
  toggle_vendor.py on  <同样参数>

把 `vendor_available: true,` 改成 `// [pandora] vendor_available: true,` 及反向。
只在该 name 所在模块块内（name 之后 40 行内）匹配，避免误伤同文件其它模块。
"""
import os
import re
import sys

MARK = "// [pandora] vendor_available: true,"
ROOT = "/root/los24"


def toggle(path, module, enable):
    full = os.path.join(ROOT, path)
    if not os.path.exists(full):
        return "MISS  %s" % path

    lines = open(full, encoding="utf-8").read().split("\n")
    start = None
    for i, ln in enumerate(lines):
        if re.search(r'name:\s*"%s"' % re.escape(module), ln):
            start = i
            break
    if start is None:
        return "NOMOD %s" % module

    for i in range(start, min(start + 40, len(lines))):
        s = lines[i].strip()
        if s == "vendor_available: true,":
            if enable:
                return "SKIP  %s 已开启" % module
            lines[i] = lines[i].replace("vendor_available: true,", MARK)
            open(full, "w", encoding="utf-8").write("\n".join(lines))
            return "OFF   %s 行%d" % (module, i + 1)
        if s == MARK:
            if not enable:
                return "SKIP  %s 已关闭" % module
            lines[i] = lines[i].replace(MARK, "vendor_available: true,")
            open(full, "w", encoding="utf-8").write("\n".join(lines))
            return "ON    %s 行%d" % (module, i + 1)

    return "NOFLAG %s（模块内无该标记）" % module


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    enable = sys.argv[1] == "on"
    for spec in sys.argv[2:]:
        path, _, module = spec.partition(":")
        print(toggle(path, module, enable))
    return 0


if __name__ == "__main__":
    sys.exit(main())
