#!/bin/bash
# 补齐 manifest 组（pdk 组含 prebuilts/clang、prebuilts/build-tools 等构建必需项）
set -o pipefail
ROOT=/root/twrp
REPO=/root/repo-tool/repo
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

cd "$ROOT" || exit 9

echo "=== 当前组 ==="
"$REPO" info 2>/dev/null | grep -i "Manifest groups" | head -2

echo "=== 用 default,pdk,platform-linux 同步 ==="
timeout 500 "$REPO" sync -g default,pdk,platform-linux -c -j4 --no-tags >> /root/twrp_sync.log 2>&1
echo "rc=$?"
tail -5 /root/twrp_sync.log

echo "=== 关键路径复查 ==="
for p in prebuilts/clang/host/linux-x86 prebuilts/build-tools/linux-x86/bin/ninja; do
  [ -e "$p" ] && echo "OK   $p" || echo "MISS $p"
done
du -sh "$ROOT"
