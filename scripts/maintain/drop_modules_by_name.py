#!/usr/bin/env python3
"""按模块名从 blob 包中剔除对应文件。

用途：
  soong 报 "PRODUCT_PACKAGES includes non-existent modules" 时（例如 32 位库
  在 64 位-only 构建里不会生成模块），把模块名列表喂进来，脚本反查 Android.bp
  里的 srcs 路径，删除文件与 proprietary-files.txt 条目。

用法:
  drop_modules_by_name.py <module_list_file>
  drop_modules_by_name.py --from-log <build_log> --marker <标记>
"""
import os
import re
import sys

ROOT = "/root/los24/vendor/xiaomi/sm8850-common"
BP = os.path.join(ROOT, "Android.bp")
LIST = os.path.join(ROOT, "proprietary-files.txt")


def modules_from_log(log, marker):
    txt = open(log, encoding="utf-8", errors="ignore").read()
    idx = txt.find(marker)
    if idx != -1:
        txt = txt[idx:]
    # 取 "Offending entries:" 之后的 blob_ 行
    out = set()
    grab = False
    for line in txt.split("\n"):
        if "Offending entries:" in line:
            grab = True
            continue
        if grab:
            s = line.strip()
            if s.startswith("blob_"):
                out.add(s)
            elif s == "" or s.startswith("["):
                if out:
                    grab = False
    return sorted(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2

    if sys.argv[1] == "--from-log":
        mods = modules_from_log(sys.argv[2], sys.argv[4] if len(sys.argv) > 4 else "")
    else:
        mods = [l.strip() for l in open(sys.argv[1], encoding="utf-8") if l.strip().startswith("blob_")]

    if not mods:
        print("没有模块名")
        return 0

    bp = open(BP, encoding="utf-8").read()
    files = []
    for m in mods:
        # 定位模块块，取 srcs
        pat = re.compile(r'name:\s*"%s",(.*?)\n\}' % re.escape(m), re.S)
        mm = pat.search(bp)
        if not mm:
            continue
        for s in re.findall(r'srcs:\s*\["([^"]+)"\]', mm.group(1)):
            files.append(s)

    print("模块 %d 个，定位到源文件 %d 个" % (len(mods), len(files)))

    # 删除 proprietary-files.txt 条目
    lines = open(LIST, encoding="utf-8").read().split("\n")
    drop = set(f.replace("proprietary/", "", 1) for f in files)
    kept = [l for l in lines if l.lstrip("-") not in drop]
    print("清单删除 %d 条，剩余 %d 条" % (len(lines) - len(kept), len(kept)))
    open(LIST, "w", encoding="utf-8").write("\n".join(kept))

    # 删除文件
    n = 0
    for f in files:
        p = os.path.join(ROOT, f)
        for x in (p, p + ".link"):
            if os.path.exists(x):
                os.remove(x)
                n += 1
    print("删除文件 %d 个" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
