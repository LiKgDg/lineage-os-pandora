#!/usr/bin/env python3
"""补齐 LineageOS 源码树中未检出的项目。

背景：repo sync 即使带 -j8 跑满时间，也会漏掉部分项目——工作区里没有，
但 repo 认为已同步，下次 sync 依然跳过。表现为编译时报核心目录不存在
（如 system/sepolicy、frameworks/base、prebuilts/clang）。

更麻烦的是，被 manifest group 过滤的项目连 `repo list` 都不列，
只能直接解析 XML 才能发现。

用法：
    los_fill_missing.py <源码树根> [--sync] [--dry-run]

不带 --sync 只报告；带 --sync 会按路径逐个定向同步。
"""

import glob
import os
import subprocess
import sys
import xml.etree.ElementTree as ET


def manifest_paths(root):
    """从 default.xml 与 snippets 里收集所有 project path。"""
    mdir = os.path.join(root, ".repo", "manifests")
    files = [os.path.join(mdir, "default.xml")]
    files += sorted(glob.glob(os.path.join(mdir, "snippets", "*.xml")))

    paths = set()
    for f in files:
        if not os.path.isfile(f):
            continue
        try:
            tree = ET.parse(f)
        except ET.ParseError as e:
            print("  解析失败 %s: %s" % (os.path.basename(f), e))
            continue
        for proj in tree.getroot().iter("project"):
            p = proj.get("path")
            if p:
                paths.add(p)
    return sorted(paths)


def missing(root, paths, excludes):
    out = []
    for p in paths:
        if any(p == e or p.startswith(e.rstrip("/") + "/") for e in excludes):
            continue
        if not os.path.exists(os.path.join(root, p)):
            out.append(p)
    return out


def repo_bin(root):
    for cand in (os.path.join(root, ".repo", "repo", "repo"),
                 "/root/repo-tool/repo"):
        if os.access(cand, os.X_OK):
            return cand
    return "repo"


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    root = os.path.abspath(sys.argv[1])
    do_sync = "--sync" in sys.argv
    dry = "--dry-run" in sys.argv

    # GKI 内核源码树（kernel/platform/kernel-*）用不到：本设备走预编译内核。
    excludes = ["kernel/platform/"]
    for i, a in enumerate(sys.argv):
        if a == "--exclude" and i + 1 < len(sys.argv):
            excludes.append(sys.argv[i + 1])

    paths = manifest_paths(root)
    miss = missing(root, paths, excludes)

    print("manifest 项目总数: %d" % len(paths))
    print("未检出: %d" % len(miss))
    for p in miss:
        print("  MISS %s" % p)

    if not miss or not do_sync or dry:
        return 0 if not miss else 1

    rb = repo_bin(root)
    batch = 8
    for i in range(0, len(miss), batch):
        chunk = miss[i:i + batch]
        print("\n=== sync %d/%d: %s" % (i + 1, len(miss), " ".join(chunk)))
        r = subprocess.run([rb, "sync", "-c", "-j4"] + chunk, cwd=root)
        if r.returncode != 0:
            print("  本批失败，继续下一批")

    still = missing(root, paths, excludes)
    print("\n=== 结果：仍未检出 %d" % len(still))
    for p in still:
        print("  STILL %s" % p)
    return 0 if not still else 1


if __name__ == "__main__":
    sys.exit(main())
