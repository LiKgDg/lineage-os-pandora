#!/usr/bin/env python3
"""为 A17 blob 包补 qcril 数据库 SQL 的 filegroup。

背景：
  device/xiaomi/sm8850-common/qcril-database/Android.bp 的 genrule
  qcril_config_database 依赖：

      //vendor/xiaomi/sm8850-common:proprietary_rildb_config_sql_files
      //vendor/xiaomi/sm8850-common:proprietary_rildb_other_sql_files

  A16 的 vendor Android.bp 里有这两个 filegroup（手工维护），
  但 tools/gen_vendor_bp.py 只按文件生成 blob_* 模块，不产出 filegroup，
  于是 soong 报 depends on undefined module。

做法：
  扫描 proprietary/vendor/etc/qcril_database/upgrade/{config,other}/*.sql，
  动态生成两个 filegroup 追加到 Android.bp。

用法:
  fix_rildb_filegroups.py [--revert]
"""
import os
import re
import sys

ROOT = "/root/los24/vendor/xiaomi/sm8850-common"
BP = os.path.join(ROOT, "Android.bp")
BASE = os.path.join(ROOT, "proprietary/vendor/etc/qcril_database/upgrade")

GROUPS = [
    ("proprietary_rildb_config_sql_files", "config"),
    ("proprietary_rildb_other_sql_files", "other"),
]
MARK = "// pandora-fix: qcril db filegroups (gen_vendor_bp.py 不产出 filegroup)"


def collect(sub):
    d = os.path.join(BASE, sub)
    if not os.path.isdir(d):
        return []
    files = sorted(f for f in os.listdir(d) if f.endswith(".sql"))
    return ["proprietary/vendor/etc/qcril_database/upgrade/%s/%s" % (sub, f) for f in files]


def build_block():
    out = ["\n" + MARK + "\n"]
    for name, sub in GROUPS:
        srcs = collect(sub)
        if not srcs:
            continue
        out.append("filegroup {")
        out.append('    name: "%s",' % name)
        out.append("    srcs: [")
        for s in srcs:
            out.append('        "%s",' % s)
        out.append("    ],")
        out.append("}")
        out.append("")
    return "\n".join(out)


def main():
    text = open(BP, encoding="utf-8").read()
    revert = "--revert" in sys.argv

    if revert:
        idx = text.find(MARK)
        if idx == -1:
            print("SKIP: not patched")
            return 0
        open(BP, "w", encoding="utf-8").write(text[:idx].rstrip() + "\n")
        print("REVERTED")
        return 0

    if MARK in text:
        print("SKIP: already patched")
        return 0

    block = build_block()
    if "filegroup {" not in block:
        print("FAIL: 没找到 sql 文件")
        return 1

    open(BP, "w", encoding="utf-8").write(text.rstrip() + "\n" + block)
    print("PATCHED")
    for name, sub in GROUPS:
        print("  %s: %d 个 sql" % (name, len(collect(sub))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
