#!/bin/bash
# 从 pandora 的 stock 分区镜像组装 device/xiaomi/pandora-kernel
#
# 输入（由 tools/payload_dump.py 从完整 OTA 提取，均经 sha256 校验）：
#   /root/pandora-dtbo/{boot,vendor_boot,dtbo,vendor_dlkm,system_dlkm}.img
# 输出：
#   /root/los24/device/xiaomi/pandora-kernel/{kernel,dtbo.img,dtb/,
#       vendor_ramdisk/,vendor_dlkm/,system_dlkm/,system_dlkm_flatten/}
set -e

SRC=/root/pandora-dtbo
VB=/root/pandora-vb
BOOT=/root/pandora-boot
# 输出目录可覆盖：默认直接写入源码树；传参可先落到暂存目录
K=${1:-/root/los24/device/xiaomi/pandora-kernel}
VER=6.12.23-android16-5-g75e9b1c7ae7c-abogki463945075-4k

echo "=== 前置检查 ==="
for f in "$SRC/boot.img" "$SRC/vendor_boot.img" "$SRC/dtbo.img" \
         "$SRC/vendor_dlkm.img" "$SRC/system_dlkm.img"; do
    [ -s "$f" ] || { echo "缺失: $f"; exit 1; }
done
[ -s "$BOOT/kernel" ] || { echo "缺失: $BOOT/kernel（先跑 unpack_bootimg）"; exit 1; }
[ -s "$VB/dtb" ] || { echo "缺失: $VB/dtb（先跑 unpack_bootimg）"; exit 1; }
echo "OK"

echo
echo "=== 解 vendor_ramdisk（LZ4+cpio）==="
rm -rf /tmp/vr /tmp/vr.cpio
lz4 -d -f "$VB/vendor_ramdisk00" /tmp/vr.cpio >/dev/null 2>&1
mkdir -p /tmp/vr
(cd /tmp/vr && cpio -idmu --quiet < /tmp/vr.cpio)
echo "vendor_ramdisk .ko: $(ls /tmp/vr/lib/modules/*.ko 2>/dev/null | wc -l)"

echo "=== 解 vendor_dlkm（EROFS）==="
rm -rf /tmp/vd
fsck.erofs --extract=/tmp/vd "$SRC/vendor_dlkm.img" >/dev/null 2>&1 || true
echo "vendor_dlkm .ko: $(ls /tmp/vd/lib/modules/*.ko 2>/dev/null | wc -l)"

echo "=== 解 system_dlkm（EROFS）==="
rm -rf /tmp/sd
fsck.erofs --extract=/tmp/sd "$SRC/system_dlkm.img" >/dev/null 2>&1 || true
echo "system_dlkm 版本目录: $(ls /tmp/sd/lib/modules 2>/dev/null | tr '\n' ' ')"
echo "system_dlkm_flatten .ko: $(ls /tmp/sd/flatten/lib/modules/*.ko 2>/dev/null | wc -l)"

echo
echo "=== 组装 $K ==="
rm -rf "$K"
mkdir -p "$K"/{dtb,vendor_ramdisk,vendor_dlkm,system_dlkm,system_dlkm_flatten}

# 内核
cp "$BOOT/kernel" "$K/kernel"
chmod 644 "$K/kernel"

# 板级 dtbo
cp "$SRC/dtbo.img" "$K/dtbo.img"

# SoC 级 dtb（拆分并校验还原）
python3 "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/split_dtb.py" \
    "$VB/dtb" "$K/dtb"

# 模块
cp -a /tmp/vr/lib/modules/. "$K/vendor_ramdisk/"
cp -a /tmp/vd/lib/modules/. "$K/vendor_dlkm/"
cp -a "/tmp/sd/lib/modules/$VER/." "$K/system_dlkm/"
cp -a /tmp/sd/flatten/lib/modules/. "$K/system_dlkm_flatten/"

# 清理 Windows 无关文件
find "$K" -name ".*" -maxdepth 2 -type f -delete 2>/dev/null || true

echo
echo "=== 校验 ==="
printf 'kernel          : %s  %s\n' "$(stat -c %s "$K/kernel")" "$(sha256sum "$K/kernel" | cut -d' ' -f1)"
printf 'dtbo.img        : %s  %s\n' "$(stat -c %s "$K/dtbo.img")" "$(sha256sum "$K/dtbo.img" | cut -d' ' -f1)"
printf 'dtb 文件数      : %s\n' "$(ls "$K/dtb" | wc -l)"
printf 'vendor_ramdisk  : %s 个 .ko, modules.load=%s\n' \
    "$(ls "$K/vendor_ramdisk"/*.ko 2>/dev/null | wc -l)" \
    "$([ -f "$K/vendor_ramdisk/modules.load" ] && echo 有 || echo 无)"
printf 'vendor_dlkm     : %s 个 .ko, modules.load=%s\n' \
    "$(ls "$K/vendor_dlkm"/*.ko 2>/dev/null | wc -l)" \
    "$([ -f "$K/vendor_dlkm/modules.load" ] && echo 有 || echo 无)"
printf 'system_dlkm     : %s 项\n' "$(ls "$K/system_dlkm" | wc -l)"
printf 'system_dlkm_flat: %s 个 .ko\n' "$(ls "$K/system_dlkm_flatten"/*.ko 2>/dev/null | wc -l)"
echo "总体积: $(du -sh "$K" | cut -f1)"
