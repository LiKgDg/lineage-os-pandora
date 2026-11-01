#!/usr/bin/env python3
"""从 blob 包中剔除与 AOSP 自编译模块冲突的文件。

背景：
  A17 的 vendor 分区包含大量 AOSP 也会从源码编译的库（libbinder/libc++/libcutils...）。
  全量复制后，soong 在打包 vendor 镜像时报：

      packaging conflict at lib64/libbinder.so

做法：
  读取冲突路径清单，从 proprietary-files.txt 删除对应条目、
  删除 proprietary/ 下的文件（含 .link），再由调用方重新生成 Android.bp。

用法:
  drop_conflicting_blobs.py <conflict_list_file>
  drop_conflicting_blobs.py --from-log <build_log> [--marker <标记>]
"""
import os
import re
import sys

ROOT = "/root/los24/vendor/xiaomi/sm8850-common"
PARTS = ["vendor", "odm", "system_ext", "product", "system"]


def read_conflicts_from_log(log, marker):
    txt = open(log, encoding="utf-8", errors="ignore").read()
    if marker:
        idx = txt.find(marker)
        if idx != -1:
            txt = txt[idx:]
    return sorted(set(re.findall(r"packaging conflict at ([^:\s]+):", txt)))


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    if sys.argv[1] == "--from-log":
        paths = read_conflicts_from_log(sys.argv[2], sys.argv[4] if len(sys.argv) > 4 else "")
    else:
        paths = [l.strip() for l in open(sys.argv[1], encoding="utf-8") if l.strip()]

    if not paths:
        print("没有冲突路径")
        return 0

    # 定位每个冲突路径在哪些分区存在（可能多个分区都有，需全部删除）
    targets = []  # (partition, relpath)
    for p in paths:
        for part in PARTS:
            f = os.path.join(ROOT, "proprietary", part, p)
            if os.path.exists(f) or os.path.exists(f + ".link"):
                targets.append((part, p))

    print("冲突路径 %d 个，在 blob 包中定位到 %d 个" % (len(paths), len(targets)))

    # 从 proprietary-files.txt 删除
    lst = os.path.join(ROOT, "proprietary-files.txt")
    lines = open(lst, encoding="utf-8").read().split("\n")
    drop = set("%s/%s" % (part, rel) for part, rel in targets)
    kept = [l for l in lines if l.lstrip("-") not in drop]
    removed = len(lines) - len(kept)
    open(lst, "w", encoding="utf-8").write("\n".join(kept))
    print("proprietary-files.txt: 删除 %d 条，剩余 %d 条" % (removed, len(kept)))

    # 删除文件
    n_del = 0
    for part, rel in targets:
        f = os.path.join(ROOT, "proprietary", part, rel)
        for x in (f, f + ".link"):
            if os.path.exists(x):
                os.remove(x)
                n_del += 1
    print("删除文件 %d 个" % n_del)

    # 清理空目录
    for part, rel in targets:
        d = os.path.dirname(os.path.join(ROOT, "proprietary", part, rel))
        while d.startswith(os.path.join(ROOT, "proprietary")):
            try:
                os.rmdir(d)
            except OSError:
                break
            d = os.path.dirname(d)

    return 0


if __name__ == "__main__":
    sys.exit(main())
