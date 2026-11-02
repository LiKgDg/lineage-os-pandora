#!/bin/bash
# 用 STAGE 里已有的模块集，构造一个假的 out/target/product/pandora，
# 验证 verify_kernel_modules.sh 能正确判定（LOS 树应 FAIL，stock 树应 PASS）。
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_ramdisks
ensure_stock_dlkm_mount vendor_dlkm
ensure_stock_dlkm_mount system_dlkm

W="$WORK"
ROOT="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os"
FAKE="$STAGE/fakeout"
LOS="$FAKE/los/target/product/pandora"
STK="$FAKE/stock/target/product/pandora"

mkdir -p "$STAGE/mnt/los_vd" "$STAGE/mnt/los_sd"
mountpoint -q "$STAGE/mnt/los_vd" || mount -o loop,ro "$IMGS/vendor_dlkm.img" "$STAGE/mnt/los_vd" || exit 9
mountpoint -q "$STAGE/mnt/los_sd" || mount -o loop,ro "$IMGS/system_dlkm.img" "$STAGE/mnt/los_sd" || exit 9

build_tree() {   # $1=目标  $2=vb源  $3=vd源  $4=sd源(根)  $5=kernel
  local t="$1"
  rm -rf "$t"
  mkdir -p "$t/vendor_ramdisk/lib/modules" \
           "$t/vendor_dlkm/lib/modules" \
           "$t/system_dlkm/flatten/lib/modules"
  cp -a "$2"/. "$t/vendor_ramdisk/lib/modules"/
  cp -a "$3"/. "$t/vendor_dlkm/lib/modules"/
  # 版本化目录
  local ver
  ver=$(find "$4/lib/modules" -maxdepth 1 -type d -name '6.12.*' | head -1)
  mkdir -p "$t/system_dlkm/lib/modules/$(basename "$ver")"
  cp -a "$ver"/. "$t/system_dlkm/lib/modules/$(basename "$ver")"/
  cp -a "$4/flatten/lib/modules"/. "$t/system_dlkm/flatten/lib/modules"/
  [ -n "${5:-}" ] && cp "$5" "$t/kernel"
  echo "  建好 $t"
}

echo "== 构造 LOS 树（应为 FAIL）=="
build_tree "$LOS" "$STAGE/vb/los/lib/modules" "$STAGE/mnt/los_vd/lib/modules" \
           "$STAGE/mnt/los_sd" "$STAGE/los_kernel.bin"
echo "== 构造 stock 树（应为 PASS）=="
build_tree "$STK" "$STAGE/vb/stock/lib/modules" "$STAGE/mnt/stock_vendor_dlkm/lib/modules" \
           "$STAGE/mnt/stock_system_dlkm" "$STAGE/los_kernel.bin"

echo
echo "########## 1. LOS 树 ##########"
bash "$ROOT/scripts/maintain/verify_kernel_modules.sh" --out "$LOS" -q
echo "exit=$?"

echo
echo "########## 2. stock 树 ##########"
bash "$ROOT/scripts/maintain/verify_kernel_modules.sh" --out "$STK" -q
echo "exit=$?"

echo
echo "########## 3. 不存在目录（应为 exit 2）##########"
bash "$ROOT/scripts/maintain/verify_kernel_modules.sh" --out /nonexistent >/dev/null 2>&1
echo "exit=$?（应为 2）"

umount "$STAGE/mnt/los_vd" "$STAGE/mnt/los_sd" 2>/dev/null
