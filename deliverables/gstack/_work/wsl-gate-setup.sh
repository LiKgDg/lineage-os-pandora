#!/bin/bash
# 一次跑完：从只读源重建 stock/LOS 模块集 → 组装 fixed-* → 跑门禁实测。
# 为什么一次跑完：WSL 空闲会重启，/root 不保留；且 _work/ 下的大文件可能被其他成员清理，
# 所以本脚本只依赖 **只读源**（OTA zip 与 LOS images/），不依赖任何中间产物。
set -u
W="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
IMGS="$W/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"
WORK="$W/deliverables/gstack/_work"
B=/root/work/gstack/qa
SETS=$B/sets
SRC=$B/src
MNT=$B/mnt

echo "== 0. 整目录重建（旧世代 .ko 残留是本次事故同源风险）=="
rm -rf "$B"; mkdir -p "$SETS" "$SRC" "$MNT"/{los_vd,stock_vd,los_sd,stock_sd,los_vb,stock_vb}

echo "== 1. 从 stock OTA 的 payload.bin 提 3 个分区（只读源，不复用中间产物）=="
python3 "$WORK/wsl_extract_part.py" --out "$SRC" vendor_boot vendor_dlkm system_dlkm || exit 1

echo "== 2. vendor_boot ramdisk → cpio =="
python3 "$WORK/wsl-vb2cpio.py" "$SRC/stock_vendor_boot.img"          "$SRC/stock_vb.cpio" || exit 1
python3 "$WORK/wsl-vb2cpio.py" "$IMGS/vendor_boot.img"               "$SRC/los_vb.cpio"   || exit 1

echo "== 3. 解 cpio =="
(cd "$MNT/los_vb"   && cpio -idm --quiet < "$SRC/los_vb.cpio")
(cd "$MNT/stock_vb" && cpio -idm --quiet < "$SRC/stock_vb.cpio")

echo "== 4. 挂载 dlkm =="
mount -o loop,ro "$IMGS/vendor_dlkm.img"        "$MNT/los_vd"   || exit 1
mount -t erofs -o loop,ro "$SRC/stock_vendor_dlkm.img"  "$MNT/stock_vd" || exit 1
mount -o loop,ro "$IMGS/system_dlkm.img"        "$MNT/los_sd"   || exit 1
mount -t erofs -o loop,ro "$SRC/stock_system_dlkm.img"  "$MNT/stock_sd" || exit 1

# flatten <src_dir> <dst_set> [modules.load]
flatten() {
  local src="$1" dst="$2" ml="${3:-}" n=0 coll=0
  mkdir -p "$dst"
  while IFS= read -r f; do
    local b; b=$(basename "$f")
    [ -e "$dst/$b" ] && coll=$((coll+1))
    cp -f "$f" "$dst/$b"; n=$((n+1))
  done < <(find "$src" -name '*.ko' -type f 2>/dev/null)
  [ -n "$ml" ] && [ -f "$ml" ] && cp -f "$ml" "$dst/modules.load"
  printf '   %-22s %4d .ko  冲突 %d  modules.load=%s\n' \
     "$(basename "$dst")" "$n" "$coll" \
     "$([ -f "$dst/modules.load" ] && wc -l < "$dst/modules.load" || echo 无)"
}

echo "== 5. 拍平 =="
flatten "$MNT/los_vb/lib/modules"   "$SETS/los-vb"   "$MNT/los_vb/lib/modules/modules.load"
flatten "$MNT/stock_vb/lib/modules" "$SETS/stock-vb" "$MNT/stock_vb/lib/modules/modules.load"
flatten "$MNT/los_vd/lib/modules"   "$SETS/los-vd"   "$MNT/los_vd/lib/modules/modules.load"
flatten "$MNT/stock_vd/lib/modules" "$SETS/stock-vd" "$MNT/stock_vd/lib/modules/modules.load"
LOSSD=$(basename "$(ls -d "$MNT"/los_sd/lib/modules/*/ | head -1)")
STOSD=$(basename "$(ls -d "$MNT"/stock_sd/lib/modules/*/ | head -1)")
echo "   system_dlkm 版本目录: LOS=$LOSSD"
flatten "$MNT/los_sd/lib/modules/$LOSSD"    "$SETS/los-sd-ver"    "$MNT/los_sd/lib/modules/$LOSSD/modules.load"
flatten "$MNT/stock_sd/lib/modules/$STOSD"  "$SETS/stock-sd-ver"  "$MNT/stock_sd/lib/modules/$STOSD/modules.load"
flatten "$MNT/los_sd/flatten/lib/modules"   "$SETS/los-sd-flat"   "$MNT/los_sd/flatten/lib/modules/modules.load"
flatten "$MNT/stock_sd/flatten/lib/modules" "$SETS/stock-sd-flat" "$MNT/stock_sd/flatten/lib/modules/modules.load"

umount "$MNT/los_vd" "$MNT/stock_vd" "$MNT/los_sd" "$MNT/stock_sd"

echo "== 6. 方案 A：stock 同名 .ko 覆盖 LOS =="
subst() {
  local l="$1" s="$2" d="$3" rep=0 same=0 gap=0 g=""
  rm -rf "$d"; cp -a "$l" "$d"
  for f in "$l"/*.ko; do
    local b; b=$(basename "$f")
    if [ -f "$s/$b" ]; then
      if cmp -s "$f" "$s/$b"; then same=$((same+1)); else cp -f "$s/$b" "$d/$b"; rep=$((rep+1)); fi
    else gap=$((gap+1)); g="$g $b"; fi
  done
  printf '   %-22s 替换 %3d  相同 %3d  stock无同名 %d%s\n' "$(basename "$d")" "$rep" "$same" "$gap" "$g"
}
subst "$SETS/los-vb"      "$SETS/stock-vb"      "$SETS/fixed-vb"
subst "$SETS/los-vd"      "$SETS/stock-vd"      "$SETS/fixed-vd"
subst "$SETS/los-sd-flat" "$SETS/stock-sd-flat" "$SETS/fixed-sd-flat"

echo "== 7. 清 modules.load：删悬空 + 去重 =="
clean_load() {
  local d="$1" ml="$1/modules.load" a b c
  [ -f "$ml" ] || { echo "   $(basename "$d"): 无 modules.load"; return 0; }
  a=$(awk '{print $1}' "$ml" | grep -v '^#' | grep -v '^$' | wc -l)
  awk -v d="$d" 'NR==FNR{h[$0]=1;next}{ if(h[$1]) print $1 }' \
      <(cd "$d" && ls *.ko 2>/dev/null) \
      <(awk '{print $1}' "$ml" | grep -v '^#' | grep -v '^$') > "$d/.ml2"
  b=$(wc -l < "$d/.ml2")
  awk '!seen[$0]++' "$d/.ml2" > "$d/.ml3"; c=$(wc -l < "$d/.ml3")
  mv "$d/.ml3" "$ml"; rm -f "$d/.ml2"
  echo "   $(basename "$d"): 原 $a 条 → 去悬空 $b 条 → 去重 $c 条"
}
clean_load "$SETS/fixed-vb"
clean_load "$SETS/fixed-vd"

echo
echo "== 模块集清单 =="
for s in "$SETS"/*/; do
  printf '  %-16s %4s .ko  %s modules.load\n' "$(basename "$s")" \
    "$(ls "$s"*.ko 2>/dev/null | wc -l)" \
    "$([ -f "$s/modules.load" ] && wc -l < "$s/modules.load" || echo '-')"
done
