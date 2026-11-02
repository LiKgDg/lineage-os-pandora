#!/bin/bash
# 全量统计两侧 vendor_boot 模块的 module_layout CRC。自包含：缺 ramdisk 就自己解。
# 判据：内核期望 0x797f2b3e（6.12.69/android16-6）；0xe976b219 = 6.12.23/android16-5 旧世代。
set -u
source "$(dirname "$0")/wsl-common.sh"
ensure_ramdisks

EXPECT=0x797f2b3e

echo "########## 抽样：binder_gki.ko / arm_smmu.ko ##########"
for side in los stock; do
  for m in binder_gki.ko arm_smmu.ko; do
    f="$STAGE/vb/$side/lib/modules/$m"
    [ -f "$f" ] || { echo "  $side/$m: 不存在"; continue; }
    printf "  %-5s %-16s %s\n" "$side" "$m" "$(crc_of "$f")"
  done
done

echo
echo "########## 全量分布 ##########"
for side in los stock; do
  echo "-- $side vendor_boot --"
  find "$STAGE/vb/$side/lib/modules" -name '*.ko' -print0 \
    | xargs -0 -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | awk "\$2==\"module_layout\"{print \$1}"' \
    | sort | uniq -c | sort -rn | awk -v e="$EXPECT" '{tag=($2==e)?"OK":"MISMATCH"; printf "   %6s  %s  %s\n", $1, $2, tag}'
done

echo
echo "########## 判定 ##########"
bad=$(find "$STAGE/vb/los/lib/modules" -name '*.ko' -print0 \
      | xargs -0 -n1 -P8 sh -c 'modprobe --dump-modversions "$0" 2>/dev/null | awk "\$2==\"module_layout\"{print \$1}"' \
      | grep -vc "^$EXPECT$" || true)
if [ "${bad:-0}" -gt 0 ]; then
  echo "FAIL: LOS vendor_boot 有 $bad 个模块的 CRC 不等于 $EXPECT"
  exit 1
fi
echo "PASS: LOS vendor_boot 全部模块 CRC == $EXPECT"
