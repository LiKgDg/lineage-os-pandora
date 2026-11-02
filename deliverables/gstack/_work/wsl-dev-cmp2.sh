#!/bin/bash
# 修正版：实机运行时模块 vs 清单（剥 .ko 后缀）；并核对未加载项的文件是否存在
set -u
DEV="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work/device-pixelos/dump"
PXVB=/root/work/pixelos/vb/lib/modules
LOSVB=/root/work/gstack/vb/los/lib/modules
STKVB=/root/work/gstack/vb/stock/lib/modules
VD="$DEV/_vendor_dlkm_lib_modules_modules.load"

python3 - "$DEV/lsmod.txt" "$PXVB" "$LOSVB" "$STKVB" "$VD" <<'PY'
import sys, os

def loaded(p):
    s = set()
    for line in open(p, encoding="utf-8", errors="replace"):
        f = line.split()
        if f and f[0] != "Module":
            s.add(f[0])
    return s

def load_list(p):
    return [l.strip() for l in open(p, encoding="utf-8", errors="replace") if l.strip()]

def names(lst):
    return {x[:-3] if x.endswith(".ko") else x for x in lst}

L        = loaded(sys.argv[1])
px_dir, los_dir, stk_dir = sys.argv[2], sys.argv[3], sys.argv[4]
px_vb    = load_list(os.path.join(px_dir, "modules.load"))
los_vb   = load_list(os.path.join(los_dir, "modules.load"))
stk_vb   = load_list(os.path.join(stk_dir, "modules.load"))
vd       = load_list(sys.argv[5])

print(f"  实机已加载          : {len(L)}")
print(f"  PixelOS vb 清单     : {len(px_vb)} 条 / 唯一 {len(names(px_vb))}")
print(f"  LOS     vb 清单     : {len(los_vb)} 条 / 唯一 {len(names(los_vb))}")
print(f"  stock   vb 清单     : {len(stk_vb)} 条 / 唯一 {len(names(stk_vb))}")
print(f"  实机 vd 清单        : {len(vd)} 条 / 唯一 {len(names(vd))}")

print()
print("=== A. 各清单的「已加载率」 ===")
for tag, lst in (("PixelOS vb", px_vb), ("stock vb", stk_vb), ("LOS vb", los_vb), ("实机 vd", vd)):
    n = names(lst)
    hit = len(n & L)
    print(f"  {tag:12s} 唯一 {len(n):3d}，实机已加载 {hit:3d}，未加载 {len(n)-hit:3d}")

print()
print("=== B. 未加载项的文件是否存在于对应 ramdisk ===")
for m in ["gcc-chora.ko", "dispcc-chora.ko", "qnoc-chora.ko", "tcsrcc-chora.ko",
          "videocc-chora.ko", "gcc-sm4450.ko", "dispcc-sm4450.ko",
          "pinctrl-ravelin.ko", "qnoc-ravelin.ko", "phy-qcom-ufs-qmp-v4-crow.ko",
          "qcom-cpufreq-hw.ko", "bcl_soc.ko", "mi_game.ko"]:
    px = "有" if os.path.exists(os.path.join(px_dir, m)) else "无"
    st = "有" if os.path.exists(os.path.join(stk_dir, m)) else "无"
    lo = "有" if os.path.exists(os.path.join(los_dir, m)) else "无"
    ld = "已加载" if m[:-3] in L else "未加载"
    print(f"  {m:28s} PixelOS={px} stock={st} LOS={lo}   实机={ld}")

print()
print("=== C. 实机已加载、但 LOS 两份清单都不含的模块 ===")
los_all = names(los_vb) | names(vd)
extra = sorted(L - los_all)
print(f"  共 {len(extra)} 个（LOS 不会加载它们）")
for x in extra:
    print(f"    {x}")
PY
