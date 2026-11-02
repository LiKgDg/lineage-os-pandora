#!/bin/bash
# check_twrp_tree.sh —— 检查 TWRP 树的关键路径是否齐全
cd /root/twrp || exit 9
echo "=== 关键路径 ==="
for p in \
  build/make/core/main.mk \
  bootable/recovery/Android.mk \
  vendor/twrp/config/common.mk \
  external/lvgl \
  prebuilts/clang/host/linux-x86 \
  prebuilts/build-tools/linux-x86/bin/ninja \
  device/xiaomi/sm8850/BoardConfig.mk \
  device/xiaomi/sm8850/prebuilt/kernel ; do
  if [ -e "$p" ]; then echo "OK   $p"; else echo "MISS $p"; fi
done

echo "=== 顶层目录 ==="
ls -d */ 2>/dev/null | tr '\n' ' '
echo
echo "=== 体积 ==="
du -sh /root/twrp
echo "=== repo 项目统计 ==="
find .repo/projects -maxdepth 2 -name "*.git" 2>/dev/null | wc -l
