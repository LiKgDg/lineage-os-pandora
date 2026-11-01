#!/bin/bash
# 用原厂 A17 逻辑分区打包 super.img（仅 slot A）
set -e
D=/mnt/d/WSL/out/pandora/stock-super
LP=/root/los24/out/host/linux-x86/bin/lpmake
SUPER_SIZE=13421772800

cd "$D" || exit 1

echo "=== 各分区大小 ==="
TOTAL=0
ARGS=""
for p in system system_ext product vendor odm vendor_dlkm system_dlkm; do
    f="$p.img"
    [ -f "$f" ] || { echo "缺失 $f"; exit 1; }
    sz=$(stat -c %s "$f")
    # 对齐到 4096
    sz=$(( (sz + 4095) / 4096 * 4096 ))
    TOTAL=$((TOTAL + sz))
    printf "  %-14s %12d\n" "$p" "$sz"
    ARGS="$ARGS --partition ${p}_a:readonly:${sz}:main --image ${p}_a=$f"
done
echo "  合计: $TOTAL  (super: $SUPER_SIZE)"

if [ "$TOTAL" -gt "$SUPER_SIZE" ]; then
    echo "超出 super 容量，中止"; exit 1
fi

echo
echo "=== lpmake ==="
rm -f super.img
$LP \
  --device-size $SUPER_SIZE \
  --metadata-size 65536 \
  --metadata-slots 2 \
  --group main:$SUPER_SIZE \
  $ARGS \
  --block-device none \
  --output super.img \
  --sparse 2>&1 | tail -5

echo
echo "=== 产物 ==="
ls -la super.img | awk '{print $5, $9}'
echo -n "校验: "
/root/los24/out/host/linux-x86/bin/lpdump --all super.img 2>/dev/null | grep -cE "^- Name:" || echo "?"
