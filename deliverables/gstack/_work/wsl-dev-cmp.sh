#!/bin/bash
# 实机运行时模块 vs 三份清单：验证「缺失的 50 个」到底会不会被加载
set -u
DEV="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work/device-pixelos/dump"
PX=/root/work/pixelos/vb/lib/modules/modules.load
LOS=/root/work/gstack/vb/los/lib/modules/modules.load
VD_DEV="$DEV/_vendor_dlkm_lib_modules_modules.load"

python3 - "$DEV/lsmod.txt" "$PX" "$LOS" "$VD_DEV" <<'PY'
import sys, os

def lsmod_names(p):
    out = []
    for line in open(p, encoding="utf-8", errors="replace"):
        f = line.split()
        if not f or f[0] == "Module":
            continue
        out.append(f[0])
    return out

def load_names(p):
    return [l.strip() for l in open(p, encoding="utf-8", errors="replace") if l.strip()]

loaded = set(lsmod_names(sys.argv[1]))
px_vb  = set(load_names(sys.argv[2]))
los_vb = set(load_names(sys.argv[3]))
vd_dev = set(load_names(sys.argv[4]))

print(f"  实机已加载模块（/proc/modules）: {len(loaded)}")
print(f"  PixelOS vendor_boot 清单      : {len(px_vb)}")
print(f"  LOS     vendor_boot 清单      : {len(los_vb)}")
print(f"  实机 vendor_dlkm 清单         : {len(vd_dev)}")

print()
print("=== A. PixelOS vendor_boot 清单里，实机真正加载了多少 ===")
print(f"  清单 {len(px_vb)} 条，其中已加载 {len(px_vb & loaded)} 条，未加载 {len(px_vb - loaded)} 条")
if px_vb - loaded:
    print("  未加载:", ", ".join(sorted(px_vb - loaded)[:12]))

print()
print("=== B. LOS 清单 vs 实机已加载：LOS 会漏掉什么 ===")
miss = sorted(px_vb - los_vb)
print(f"  LOS 清单比 PixelOS 少 {len(miss)} 条；其中实机确实加载了的 {len([m for m in miss if m.replace('.ko','') in loaded])} 条：")
for m in miss:
    n = m.replace(".ko", "")
    if n in loaded:
        print(f"    ✓ 实机已加载: {m}")
print()
print(f"  其中实机也没加载的 {len([m for m in miss if m.replace('.ko','') not in loaded])} 条（说明是可选的）：")
for m in miss:
    n = m.replace(".ko", "")
    if n not in loaded:
        print(f"    · 未加载: {m}")

print()
print("=== C. LOS 的 8 条幽灵条目：实机是否存在同名模块 ===")
ghost = sorted(los_vb - px_vb)
for m in ghost:
    n = m.replace(".ko", "")
    print(f"    {m:24s} 实机已加载={n in loaded}")
PY
