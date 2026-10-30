#!/bin/bash
# 初始化并同步 LineageOS 24.0 源码树，供 sm8850 完整 ROM 开发使用。
#
# 可反复执行：repo sync 是增量的。
# 镜像：AOSP 走 BFSU（TUNA 排队严重），LineageOS 项目走 github。

set -o pipefail
ROOT=/root/los24
REPO=/root/repo-tool/repo
BRANCH=lineage-24.0
LOG=/root/los24_sync.log

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

mkdir -p "$ROOT"
cd "$ROOT" || exit 9

if [ ! -x .repo/repo/repo ]; then
    echo "=== repo init ($BRANCH) ==="
    "$REPO" init -u https://github.com/LineageOS/android.git \
        -b "$BRANCH" \
        -g default,pdk,platform-linux \
        --repo-url=https://github.com/GerritCodeReview/git-repo \
        --repo-rev=main --no-repo-verify 2>&1 | tail -8
fi

# 组必须通过 init 持久化；加在 sync 上不会生效。
# system/sepolicy、prebuilts/clang、prebuilts/misc、frameworks/base 都在 pdk 组。
if ! "$REPO" info 2>/dev/null | grep -q "pdk"; then
    echo "=== 补齐 manifest 组（pdk）==="
    "$REPO" init -u https://github.com/LineageOS/android.git \
        -b "$BRANCH" \
        -g default,pdk,platform-linux \
        --repo-url=https://github.com/GerritCodeReview/git-repo \
        --repo-rev=main --no-repo-verify 2>&1 | tail -6
fi

# 设备树与依赖。机型树 device/xiaomi/pandora 待阶段 D 自建。
mkdir -p .repo/local_manifests
cat > .repo/local_manifests/sm8850.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="gh" fetch="https://github.com" />

  <!-- 公共设备树：用 lolipuru 上游（比 AlexZorzi fork 新，标注 booted） -->
  <project name="lolipuru/android_device_xiaomi_sm8850-common"
           path="device/xiaomi/sm8850-common"
           remote="gh" revision="lineage-24.0" />

  <!-- vendor blobs -->
  <project name="lolipuru/android_vendor_xiaomi_sm8850-common"
           path="vendor/xiaomi/sm8850-common"
           remote="gh" revision="lineage-24.0" />

  <!-- 机型树参考：pandora 以 popsicle（17 Pro Max）为蓝本 -->
  <project name="lolipuru/android_device_xiaomi_popsicle"
           path="device/xiaomi/popsicle"
           remote="gh" revision="lineage-24.0" />

  <!-- 内核设备树与模块 -->
  <project name="lolipuru/android_kernel_xiaomi_sm8850-devicetrees"
           path="kernel/xiaomi/sm8850-devicetrees"
           remote="gh" revision="lineage-24.0" />
</manifest>
XML


echo "=== repo sync（限时，可重跑）==="
# 必须带 -g：system/sepolicy、prebuilts/clang、prebuilts/misc、frameworks/base
# 等核心项目都在 pdk 组，默认只启用 default,platform-linux 会全部跳过。
timeout 500 "$REPO" sync -c -j8 --no-clone-bundle \
    -g default,pdk,platform-linux >> "$LOG" 2>&1

rc=$?
echo "rc=$rc"
echo "=== 进度 ==="
du -sh "$ROOT" 2>/dev/null
echo "项目数: $("$REPO" list 2>/dev/null | wc -l)"
[ -f "$ROOT/device/xiaomi/sm8850-common/BoardConfigCommon.mk" ] \
    && echo "sm8850-common 已就位" || echo "sm8850-common 未到"
