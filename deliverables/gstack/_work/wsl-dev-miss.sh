#!/bin/bash
# 精确量化：LOS 清单缺的条目，实机到底加载了多少（用 fakeout 树，无需挂载）
set -u
DEV="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work/device-pixelos/dump"
LOS=/root/work/gstack/fakeout/los/target/product/pandora
LOSVD="$LOS/vendor_dlkm/lib/modules/modules.load"
LOSVB="$LOS/vendor_ramdisk/lib/modules/modules.load"
DEVVD="$DEV/_vendor_dlkm_lib_modules_modules.load"
PXVB=/root/work/pixelos/vb/lib/modules/modules.load
for f in "$LOSVD" "$LOSVB" "$DEVVD" "$PXVB" "$DEV/lsmod.txt"; do
  [ -f "$f" ] || { echo "FATAL: 缺 $f"; exit 9; }
done

python3 - "$DEV/lsmod.txt" "$LOSVD" "$DEVVD" "$PXVB" "$LOSVB" <<'PY'
import sys

def loaded(p):
    s = set()
    for line in open(p, encoding="utf-8", errors="replace"):
        f = line.split()
        if f and f[0] != "Module":
            s.add(f[0])
    return s

def names(p):
    out = set()
    for l in open(p, encoding="utf-8", errors="replace"):
        x = l.strip()
        if x:
            out.add(x[:-3] if x.endswith(".ko") else x)
    return out

L = loaded(sys.argv[1])
los_vd, dev_vd, px_vb, los_vb = (names(p) for p in sys.argv[2:6])

def report(tag, miss):
    on  = [m for m in miss if m in L]
    off = [m for m in miss if m not in L]
    print(f"\n=== {tag}：LOS 缺 {len(miss)} 条，实机已加载 {len(on)} 条，未加载 {len(off)} 条 ===")
    print("  ── 已加载（真需要）──")
    for m in on:  print(f"    ✓ {m}")
    print("  ── 未加载（可选）──")
    for m in off: print(f"    · {m}")
    return set(on)

a = report("vendor_dlkm", sorted(dev_vd - los_vd))
b = report("vendor_boot", sorted(px_vb - los_vb))

print(f"\n=== 合计：LOS 会漏加载 {len(a | b)} 个实机确实会加载的模块 ===")
print("  " + ", ".join(sorted(a | b)))

print(f"\n=== 反向：实机已加载但 LOS 两份清单都没有的 ===")
extra = sorted(L - (los_vd | los_vb))
print(f"  共 {len(extra)} 个（多为按需自动加载：网络协议族、文件系统等）")
print("  " + ", ".join(extra[:30]) + (" ..." if len(extra) > 30 else ""))
PY
