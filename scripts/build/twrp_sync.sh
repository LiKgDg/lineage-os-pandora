#!/bin/bash
# 初始化并同步 TWRP (twrp-16.0) 源码树。可反复执行，repo sync 是增量的。
set -o pipefail
ROOT=/root/twrp
REPO=/root/repo-tool/repo
LOG=/root/twrp_sync.log
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

mkdir -p "$ROOT"
cd "$ROOT" || exit 9

if [ ! -x .repo/repo/repo ]; then
  echo "=== repo init ==="
  "$REPO" init -u https://github.com/TWRP-Test/platform_manifest_twrp_aosp.git \
      -b twrp-16.0 \
      --repo-url=https://github.com/GerritCodeReview/git-repo \
      --repo-rev=main --no-repo-verify 2>&1 | tail -8
fi

mkdir -p .repo/local_manifests
cat > .repo/local_manifests/pinned.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <remote name="twrptest" fetch="https://github.com/TWRP-Test" />
  <project name="twrp_device_xiaomi_sm8850" path="device/xiaomi/sm8850"
           revision="8023035649595341e26f9b924928c0b0cd67fbd2" remote="twrptest" />
</manifest>
XML

echo "=== repo sync（限时 500s，可重跑）==="
timeout 500 "$REPO" sync -c -j4 --no-tags --no-clone-bundle >> "$LOG" 2>&1
rc=$?
echo "rc=$rc"
echo "=== 最近日志 ==="
tail -6 "$LOG"
echo "=== 体积 ==="
du -sh "$ROOT" 2>/dev/null
