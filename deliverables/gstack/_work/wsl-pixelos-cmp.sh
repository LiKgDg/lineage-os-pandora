#!/bin/bash
# PixelOS vs stock vs LOS：模块字节关系、清单差异、悬空项归属
set -u
PX=/root/work/pixelos/vb/lib/modules
GS=/root/work/gstack/vb
LOS=$GS/los/lib/modules
STK=$GS/stock/lib/modules
for d in "$PX" "$LOS" "$STK"; do [ -d "$d" ] || { echo "FATAL: 缺 $d"; exit 9; }; done

h() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

echo "########## 1. 模块字节关系（同名 .ko 的 sha256 是否相同） ##########"
python3 - "$PX" "$STK" "$LOS" <<'PY'
import sys, os, hashlib
px, stk, los = sys.argv[1:4]
def load(d):
    return {f: os.path.join(d, f) for f in os.listdir(d) if f.endswith(".ko")}
def digest(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(1 << 20), b""):
            h.update(c)
    return h.hexdigest()
P, S, L = load(px), load(stk), load(los)
print(f"  PixelOS={len(P)}  stock={len(S)}  LOS={len(L)}")
for name, A, B in (("PixelOS vs stock", P, S), ("PixelOS vs LOS", P, L)):
    common = sorted(set(A) & set(B))
    same = [n for n in common if digest(A[n]) == digest(B[n])]
    print(f"  {name}: 同名 {len(common)}，逐字节相同 {len(same)}，不同 {len(common)-len(same)}")
print(f"  PixelOS 独有文件: {sorted(set(P)-set(S))}")
print(f"  stock 独有文件:   {sorted(set(S)-set(P))}")
PY

echo
echo "########## 2. 那 8 条悬空模块在 PixelOS 里存在吗 ##########"
for m in mem_object qcom_tzmem mi_schedule metis migt miloadtrace mi_mem_epoll mi_mem_limit; do
  printf "  %-16s pixelos_vb=%-3s pixelos_vd=%-3s stock_vb=%-3s los_vb=%-3s\n" "$m.ko" \
    "$([ -f "$PX/$m.ko" ] && echo Y || echo -)" \
    "$(find /root/work/pixelos/mnt/vendor_dlkm -name "$m.ko" 2>/dev/null | head -1 | grep -q . && echo Y || echo -)" \
    "$([ -f "$STK/$m.ko" ] && echo Y || echo -)" \
    "$([ -f "$LOS/$m.ko" ] && echo Y || echo -)"
done

echo
echo "########## 3. modules.load 对账 ##########"
for tag in "LOS:$LOS" "stock:$STK" "PixelOS:$PX"; do
  name=${tag%%:*}; dir=${tag#*:}
  f="$dir/modules.load"
  if [ -f "$f" ]; then
    total=$(grep -c . "$f"); uniq=$(sort -u "$f" | grep -c .)
    dangling=0
    while read -r m; do [ -z "$m" ] && continue; [ -f "$dir/$m" ] || dangling=$((dangling+1)); done < "$f"
    printf "  %-8s 条目 %-4s 唯一 %-4s 重复 %-4s 悬空 %-3s\n" "$name" "$total" "$uniq" "$((total-uniq))" "$dangling"
  else
    printf "  %-8s 无 modules.load\n" "$name"
  fi
done

echo
echo "########## 4. LOS 的 150 条清单，PixelOS 能否全覆盖 ##########"
python3 - "$PX" "$LOS" <<'PY'
import sys, os
px, los = sys.argv[1:3]
def read(p):
    with open(os.path.join(p, "modules.load")) as f:
        return [l.strip() for l in f if l.strip()]
L, P = read(los), read(px)
missing = [m for m in L if not os.path.exists(os.path.join(px, m))]
print(f"  LOS 清单 {len(L)} 条（唯一 {len(set(L))}），PixelOS ramdisk 缺 {len(missing)} 条")
if missing:
    print("  缺失:", ", ".join(missing))
print(f"  PixelOS 清单比 LOS 多 {len(set(P)-set(L))} 条，少 {len(set(L)-set(P))} 条")
PY

echo
echo "########## 5. ramdisk 文件树差异（非模块部分） ##########"
diff <(cd /root/work/pixelos/vb && find . -type f | sort) <(cd "$GS/los" && find . -type f | sort) | head -30
