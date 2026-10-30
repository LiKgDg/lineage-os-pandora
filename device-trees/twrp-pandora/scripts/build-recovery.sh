#!/bin/bash
# build-recovery.sh —— 为 Xiaomi 17 Pro (pandora) 编译 LineageOS recovery
#
# 用法:
#   bash scripts/build-recovery.sh            # 只编 recovery（约 30-60 分钟）
#   bash scripts/build-recovery.sh bacon      # 编完整 ROM（需要 vendor blobs）
#
# 环境变量:
#   AOSP_ROOT  源码树位置，默认 /root/android/lineage
set -euo pipefail

AOSP_ROOT="${AOSP_ROOT:-/root/android/lineage}"
TARGET="${1:-recoveryimage}"
cd "$AOSP_ROOT"

# ── 前置修正 ────────────────────────────────────────────────────────
# prebuilts/misc/protobuf_vendorcompat 与 hardware/lineage/compat 定义了
# 同名的 5 个 protobuf 模块，共存时 soong 报 "already defined"。
# 保留模块更全的 hardware/lineage/compat，禁用小的那份。
DUP="prebuilts/misc/protobuf_vendorcompat/Android.bp"
if [ -f "$DUP" ]; then
    mv "$DUP" "$DUP.disabled_by_pandora"
    echo "[fix] 已禁用重复的 $DUP"
fi

# ── 构建环境 ────────────────────────────────────────────────────────
# AOSP 的 envsetup.sh 与 set -u 不兼容（build/envsetup.sh:21 直接引用 $TOP），
# 必须先关 nounset 再 source，否则 lunch 静默不定义、只看到 "command not found"。
set +u
source build/envsetup.sh >/dev/null
lunch lineage_pandora-bp4a-userdebug >/dev/null
set -u

echo "[build] $TARGET_PRODUCT / $TARGET_RELEASE / $TARGET"
echo "[build] 开始 $(date '+%F %T')"

set +u
m "$TARGET"
RC=$?
set -u

echo "[build] 结束 $(date '+%F %T')  rc=$RC"
[ "$RC" -eq 0 ] && [ -f out/target/product/pandora/recovery.img ] && \
    ls -l out/target/product/pandora/recovery.img
exit "$RC"
