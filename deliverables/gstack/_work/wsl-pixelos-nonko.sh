#!/bin/bash
# PixelOS 与 LOS 的 vendor_boot ramdisk：非模块文件是否完全一致
set -u
PX=/root/work/pixelos/vb
LS=/root/work/gstack/vb/los

python3 - "$PX" "$LS" <<'PY'
import sys, os, hashlib
px, ls = sys.argv[1:3]
def walk(root):
    out = {}
    for dp, _, fs in os.walk(root):
        for f in fs:
            p = os.path.join(dp, f)
            out[os.path.relpath(p, root)] = p
    return out
def dg(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()
A, B = walk(px), walk(ls)
print(f"  PixelOS 文件 {len(A)}，LOS 文件 {len(B)}")
print(f"  仅 PixelOS 有: {sorted(set(A) - set(B)) or '无'}")
print(f"  仅 LOS 有    : {sorted(set(B) - set(A)) or '无'}")
ko = [n for n in sorted(set(A) & set(B)) if n.endswith('.ko')]
other = [n for n in sorted(set(A) & set(B)) if not n.endswith('.ko')]
same_ko = [n for n in ko if dg(A[n]) == dg(B[n])]
diff_other = [n for n in other if dg(A[n]) != dg(B[n])]
print(f"  .ko 共 {len(ko)}，相同 {len(same_ko)}，不同 {len(ko)-len(same_ko)}")
print(f"  非 .ko 共 {len(other)}，不同 {len(diff_other)} 个")
if diff_other:
    for n in diff_other:
        print(f"    DIFF {n}  PixelOS={os.path.getsize(A[n]):,}  LOS={os.path.getsize(B[n]):,}")
PY
