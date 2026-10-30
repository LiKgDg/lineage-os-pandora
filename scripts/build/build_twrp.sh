#!/bin/bash
# TWRP recovery 前台编译脚本 —— 在 GUI 终端里运行可看到 ninja 实时进度条
#
# 用法：build_twrp.sh [并行度]
#   并行度默认 10。本机 16 核 / 23 GB，-j16 曾触发 WSL VM 重启，
#   降到 10 更稳；内存充裕时可用 12。
#
# 加速手段：
#   - ninja -j 并行（CPU 核数决定，GPU 不参与编译）
#   - 增量编译：中断后重跑从断点继续
#   - ccache 默认关闭（首次全量无收益且增加写入），需要时：
#       ENABLE_CCACHE=1 build_twrp.sh 10

set -o pipefail
cd /root/twrp || exit 9

export JAVA_HOME=/root/twrp/prebuilts/jdk/jdk21/linux-x86
export PATH="$JAVA_HOME/bin:/root/twrp/prebuilts/build-tools/linux-x86/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ── ccache（默认关闭）──────────────────────────────────────────────
if [ "${ENABLE_CCACHE:-0}" = "1" ] && command -v ccache >/dev/null 2>&1; then
    export USE_CCACHE=1
    export CCACHE_EXEC=/usr/bin/ccache
    export CCACHE_DIR=/root/.ccache
    ccache -M 40G >/dev/null 2>&1
    echo "ccache: 已启用，上限 40G"
else
    export CCACHE_DISABLE=1
    echo "ccache: 已禁用（首次全量编译无收益）"
fi

source build/envsetup.sh >/dev/null 2>&1
lunch twrp_sm8850-bp2a-eng >/dev/null 2>&1 || { echo "lunch 失败"; exit 1; }

JOBS="${1:-10}"
echo "============================================================"
echo " 目标: recoveryimage"
echo " 并行: -j$JOBS    内存: $(free -g | awk '/^Mem:/ {print $2}') GB 可用: $(free -g | awk '/^Mem:/ {print $7}') GB"
echo " 磁盘: $(df -h / | awk 'NR==2 {print $4}') 可用"
echo " 日志: /root/twrp_build.log"
echo "============================================================"

start=$(date +%s)
mka recoveryimage -j"$JOBS" 2>&1 | tee -a /root/twrp_build.log
rc=${PIPESTATUS[0]}
end=$(date +%s)

echo
echo "============================================================"
echo " 结果: rc=$rc   耗时: $(( (end - start) / 60 )) 分 $(( (end - start) % 60 )) 秒"
if [ -f out/target/product/sm8850/recovery.img ]; then
    ls -la out/target/product/sm8850/recovery.img
else
    echo " 未产出 recovery.img"
fi
echo "============================================================"
