#!/bin/bash
# make_super.sh —— 用 lpmake 把动态分区打包成 super.img
set -e
cd /root/android/lineage
LPMAKE=out/host/linux-x86/bin/lpmake
OUT=out/target/product/pandora
STOCK=/root/pandora-stock
GRP=qti_dynamic_partitions
GRP_SIZE=13419675648
DEV_SIZE=13421772800

sz() { stat -c%s "$1"; }

echo "=== 分区尺寸 ==="
for f in $OUT/system.img $OUT/system_ext.img $OUT/product.img \
         $STOCK/mi_ext.img $STOCK/vendor.img $STOCK/vendor_dlkm.img \
         $STOCK/system_dlkm.img $STOCK/odm.img; do
  printf "  %-40s %12d\n" "$(basename "$f")" "$(sz "$f")"
done

TOTAL=$(( $(sz $OUT/system.img) + $(sz $OUT/system_ext.img) + $(sz $OUT/product.img) \
        + $(sz $STOCK/mi_ext.img) + $(sz $STOCK/vendor.img) + $(sz $STOCK/vendor_dlkm.img) \
        + $(sz $STOCK/system_dlkm.img) + $(sz $STOCK/odm.img) ))
echo "=== 合计 $TOTAL B / super $DEV_SIZE B ==="

"$LPMAKE" \
  --device-size "$DEV_SIZE" \
  --metadata-size 65536 \
  --metadata-slots 3 \
  --super-name super \
  --group "$GRP:$GRP_SIZE" \
  --partition "system:readonly:$(sz $OUT/system.img):$GRP" \
  --image "system=$OUT/system.img" \
  --partition "system_ext:readonly:$(sz $OUT/system_ext.img):$GRP" \
  --image "system_ext=$OUT/system_ext.img" \
  --partition "product:readonly:$(sz $OUT/product.img):$GRP" \
  --image "product=$OUT/product.img" \
  --partition "mi_ext:readonly:$(sz $STOCK/mi_ext.img):$GRP" \
  --image "mi_ext=$STOCK/mi_ext.img" \
  --partition "vendor:readonly:$(sz $STOCK/vendor.img):$GRP" \
  --image "vendor=$STOCK/vendor.img" \
  --partition "vendor_dlkm:readonly:$(sz $STOCK/vendor_dlkm.img):$GRP" \
  --image "vendor_dlkm=$STOCK/vendor_dlkm.img" \
  --partition "system_dlkm:readonly:$(sz $STOCK/system_dlkm.img):$GRP" \
  --image "system_dlkm=$STOCK/system_dlkm.img" \
  --partition "odm:readonly:$(sz $STOCK/odm.img):$GRP" \
  --image "odm=$STOCK/odm.img" \
  --sparse \
  --output /root/super.img

ls -la /root/super.img
echo "=== 校验 metadata ==="
out/host/linux-x86/bin/lpdump /root/super.img 2>/dev/null | head -30 || true
cp /root/super.img "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/sysonly/super.img"
ls -la "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/sysonly/super.img"
