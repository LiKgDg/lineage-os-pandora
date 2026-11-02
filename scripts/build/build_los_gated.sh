#!/bin/bash
# =============================================================================
# build_los_gated.sh —— 带 KMI 门禁的 LOS 构建入口
#
# 为什么存在
#   INC-PANDORA-LOS24-001 的 P0 缺陷（内核 6.12.69 + 模块 6.12.23）在构建机上
#   100% 可查，却用四次刷机才被发现。根因不是没人知道要查，而是**没有强制入口**：
#   `m bacon` 正常结束、zip 正常产出，缺陷照样通过。
#
#   本脚本把门禁绑到构建出口：构建成功 ≠ 可出包，必须再过 KMI 门禁。
#
# 判据
#   scripts/maintain/verify_kernel_modules.sh（内部调 kmi-gate.sh，CRC 判据）
#   任一集合 FAIL 即 exit 1，并在 zip 旁留一个 .GATE-FAILED 标记，
#   避免误把失败产物刷进设备。
#
# 用法
#   bash scripts/build/build_los_gated.sh            # 增量构建 + 门禁
#   bash scripts/build/build_los_gated.sh --package  # 构建 + 门禁 + 出 fastboot 安装包
#   bash scripts/build/build_los_gated.sh --no-build # 只跑门禁（对已有产物）
# =============================================================================
set -u

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$PROJ/scripts/maintain/verify_kernel_modules.sh"
PKG="$PROJ/scripts/build/make_fastboot_package.sh"
OUT="/root/los24/out/target/product/pandora"
JOBS="${JOBS:-8}"
DO_BUILD=1
DO_PKG=0

for arg in "$@"; do
    case "$arg" in
        --no-build) DO_BUILD=0 ;;
        --package)  DO_PKG=1 ;;
    esac
done

err() { echo "ERROR: $*" >&2; }

if [ ! -f "$GATE" ]; then
    err "门禁脚本不存在：$GATE"
    exit 2
fi

# ---------------------------------------------------------------------------
# 1. 构建
# ---------------------------------------------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
    echo "[1/2] 构建（m bacon -j$JOBS）"
    cd /root/los24 || { err "构建树不存在：/root/los24"; exit 2; }
    export JAVA_HOME=/root/los24/prebuilts/jdk/jdk21/linux-x86
    export PATH="$JAVA_HOME/bin:/root/los24/prebuilts/build-tools/linux-x86/bin:$PATH"
    # shellcheck disable=SC1091
    source build/envsetup.sh >/dev/null 2>&1
    lunch lineage_pandora-trunk_staging-userdebug >/dev/null 2>&1

    if ! m bacon -j"$JOBS"; then
        err "构建失败"
        exit 1
    fi
else
    echo "[1/2] 跳过构建（--no-build）"
fi

# ---------------------------------------------------------------------------
# 2. 门禁
# ---------------------------------------------------------------------------
echo
echo "[2/2] KMI 门禁"
if bash "$GATE"; then
    rm -f "$OUT"/*.GATE-FAILED 2>/dev/null || true
    echo
    echo "✅ 构建 + 门禁均通过"

    # -----------------------------------------------------------------------
    # 3. 可选：出 fastboot 安装包
    # -----------------------------------------------------------------------
    if [ "$DO_PKG" -eq 1 ]; then
        echo
        echo "[3/3] 生成 fastboot 安装包"
        if [ -f "$PKG" ]; then
            if bash "$PKG"; then
                echo
                echo "✅ 已产出 fastboot 安装包，可直接："
                echo "   fastboot -w update <上面列出的 zip>"
            else
                err "fastboot 包生成失败"
                exit 1
            fi
        else
            err "打包脚本不存在：$PKG"
            exit 1
        fi
    else
        ls -la "$OUT"/lineage-24.0-*.zip 2>/dev/null | tail -1
        echo "   提示：加 --package 可同时产出 fastboot 安装包"
    fi
    exit 0
else
    RC=$?
    # 留标记，避免误刷
    touch "$OUT/.GATE-FAILED" 2>/dev/null || true
    echo
    err "门禁未通过（exit $RC）——产物不可刷入"
    echo "  常见原因：内核换代但模块未换（见 scripts/maintain/replace_kernel_modules.sh）"
    echo "  修复：bash scripts/maintain/replace_kernel_modules.sh --imgset <stock镜像目录> --apply"
    echo "  标记：$OUT/.GATE-FAILED"
    exit 1
fi
