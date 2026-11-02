#!/bin/bash
# 四来源 fstab 比对：LOS/stock × (vendor/etc, first_stage_ramdisk)。
# 自包含：缺的镜像会按需提取到 $STAGE（WSL 持久目录），文本证据回写 _work。
set -u
source "$(dirname "$0")/wsl-common.sh"

OUTF="$WORK/fstab-four-sources.txt"

# --- 准备：stock vendor.img（589 MB，中间态，落 STAGE） ---
if [ ! -f "$STAGE/stock_vendor.img" ]; then
  echo "== 提取 stock vendor.img 到 $STAGE（约 589 MB，耗时 1–2 分钟）=="
  python3 "$WORK/wsl_extract_part.py" --out "$STAGE" vendor || exit 9
  need "$STAGE/stock_vendor.img" "stock vendor.img"
fi

# --- 准备：两侧 ramdisk ---
ensure_ramdisks

# --- A. stock vendor/etc（EROFS 挂载） ---
mnt="$STAGE/mnt/stock_vendor"
mkdir -p "$mnt"
mountpoint -q "$mnt" || mount -t erofs -o loop,ro "$STAGE/stock_vendor.img" "$mnt" || exit 9
cp "$mnt/etc/fstab.qcom" "$STAGE/fstab-stock-vendoretc.qcom"
umount "$mnt" 2>/dev/null || true

# --- B. LOS vendor/etc（ext4 debugfs） ---
debugfs -R "dump /etc/fstab.qcom $STAGE/fstab-los-vendoretc.qcom" "$IMGS/vendor.img" 2>/dev/null
need "$STAGE/fstab-los-vendoretc.qcom" "LOS vendor/etc/fstab.qcom"

# --- C. 两侧 first_stage（从已解开的 ramdisk 里取） ---
cp "$STAGE/vb/los/first_stage_ramdisk/fstab.qcom"   "$STAGE/fstab-los-firststage.qcom"
cp "$STAGE/vb/stock/first_stage_ramdisk/fstab.qcom" "$STAGE/fstab-stock-firststage.qcom"

{
  echo "########## 四来源 sha256 ##########"
  for f in fstab-los-vendoretc.qcom fstab-los-firststage.qcom \
           fstab-stock-vendoretc.qcom fstab-stock-firststage.qcom; do
    printf "%-34s %8s B  %s\n" "$f" "$(stat -c%s "$STAGE/$f")" "$(sha256sum "$STAGE/$f" | cut -d' ' -f1)"
  done

  echo
  echo "########## userdata / metadata 行 ##########"
  for f in fstab-los-vendoretc.qcom fstab-stock-vendoretc.qcom; do
    echo "-- $f --"
    grep -E "by-name/(userdata|metadata)" "$STAGE/$f"
    echo
  done

  echo "########## userdata 行 token 级差集（按空格与逗号切分） ##########"
  norm() { grep "by-name/userdata" "$1" | tr -s ' ,' '\n' | grep -v '^$' | sort -u; }
  echo "-- 只在 stock 有 --"; comm -13 <(norm "$STAGE/fstab-los-vendoretc.qcom") <(norm "$STAGE/fstab-stock-vendoretc.qcom") | sed 's/^/   /'
  echo "-- 只在 LOS 有 --";  comm -23 <(norm "$STAGE/fstab-los-vendoretc.qcom") <(norm "$STAGE/fstab-stock-vendoretc.qcom") | sed 's/^/   /'
} | tee "$OUTF"

# --- 文本证据回写 _work ---
cp "$STAGE/fstab-los-vendoretc.qcom"   "$WORK/fstab-qcom-los.txt"
cp "$STAGE/fstab-stock-vendoretc.qcom" "$WORK/fstab-qcom-stock.txt"
echo
echo "文本证据已回写: $WORK/fstab-qcom-los.txt, $WORK/fstab-qcom-stock.txt, $OUTF"
