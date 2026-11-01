#!/usr/bin/env python3
"""按相对路径清单（如 vendor/bin/wpa_cli）从 blob 包剔除文件。"""
import os
import sys

ROOT = "/root/los24/vendor/xiaomi/sm8850-common"
LIST = os.path.join(ROOT, "proprietary-files.txt")
PARTS = ["vendor", "odm", "system_ext", "product", "system"]


def main():
    src = sys.argv[1]
    paths = [l.strip() for l in open(src, encoding="utf-8") if l.strip()]
    if not paths:
        print("清单为空")
        return 0

    # 每条形如 vendor/bin/wpa_cli（首段即分区）
    targets = []
    for p in paths:
        part, _, rel = p.partition("/")
        if part not in PARTS:
            continue
        f = os.path.join(ROOT, "proprietary", part, rel)
        if os.path.exists(f) or os.path.exists(f + ".link"):
            targets.append((part, rel, p))

    print("清单 %d 条，命中 %d 个" % (len(paths), len(targets)))

    lines = open(LIST, encoding="utf-8").read().split("\n")
    drop = set(p for _, _, p in targets)
    kept = [l for l in lines if l.lstrip("-") not in drop]
    print("proprietary-files.txt: 删除 %d 条，剩余 %d 条" % (len(lines) - len(kept), len(kept)))
    open(LIST, "w", encoding="utf-8").write("\n".join(kept))

    n = 0
    for part, rel, _ in targets:
        f = os.path.join(ROOT, "proprietary", part, rel)
        for x in (f, f + ".link"):
            if os.path.exists(x):
                os.remove(x)
                n += 1
    print("删除文件 %d 个" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
