#!/bin/bash
# 公共前置：持久 stage 目录 + 存在性断言
# 用法：在其它脚本里 `source "$(dirname "$0")/wsl-common.sh"`
#
# 规则（见报告 §5.4）：中间态落 WSL ext4 的持久目录，不进 /tmp（空闲重启会清空），
# 也不进 /mnt/c（9p 慢、缺可执行位、旧世代 .ko 会残留）。
set -u

STAGE="${STAGE:-/root/work/gstack}"
WORK="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/deliverables/gstack/_work"
IMGS="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/UotanToolbox_lineage-24.0-20261101-UNOFFICIAL-pandora.zip/images"

mkdir -p "$STAGE" || { echo "FATAL: 无法创建 STAGE=$STAGE"; exit 9; }

# 断言某个路径存在，否则带上下文退出（杜绝「find 找不到 → 输出 0 行 → 看起来像没有模块」）
need() {
  local p="$1" what="${2:-$1}"
  if [ ! -e "$p" ]; then
    echo "FATAL: 缺少 $what ($p)" >&2
    echo "       先跑对应的准备脚本，或设 STAGE=<已有 stage 目录>" >&2
    exit 9
  fi
}

# 解 vendor_boot ramdisk 到 $STAGE/vb/{los,stock}（幂等）
# 缺 cpio 时会自动调用 wsl-stage-init.sh 生成（产物全部落 STAGE，不碰 /mnt/c）
ensure_ramdisks() {
  local need_init=0
  for side in los stock; do
    [ -d "$STAGE/vb/$side/lib/modules" ] || need_init=1
  done
  if [ "$need_init" -eq 1 ]; then
    if [ ! -f "$STAGE/los_vendor_ramdisk.cpio" ] || [ ! -f "$STAGE/stock_vendor_ramdisk.cpio" ]; then
      echo "== stage 未初始化，调用 wsl-stage-init.sh =="
      bash "$(dirname "${BASH_SOURCE[0]}")/wsl-stage-init.sh" || exit 9
    fi
    for side in los stock; do
      if [ ! -d "$STAGE/vb/$side/lib/modules" ]; then
        echo "== 解 $side ramdisk 到 $STAGE/vb/$side =="
        mkdir -p "$STAGE/vb/$side"
        (cd "$STAGE/vb/$side" && cpio -idm --quiet < "$STAGE/${side}_vendor_ramdisk.cpio") || exit 9
      fi
    done
  fi
  need "$STAGE/vb/los/lib/modules"   "LOS 模块目录"
  need "$STAGE/vb/stock/lib/modules" "stock 模块目录"
}

# 挂载 stock 的 dlkm 分区（EROFS）到 $STAGE/mnt/<name>（幂等）
# 镜像按 §5.4 的裁定放在 $STAGE，不在 $WORK；缺了会先调 wsl-stage-init.sh
ensure_stock_dlkm_mount() {
  local name="$1"   # vendor_dlkm | system_dlkm
  local img="$STAGE/stock_${name}.img"
  if [ ! -f "$img" ]; then
    echo "== 缺少 stock ${name} 镜像，调用 wsl-stage-init.sh =="
    bash "$(dirname "${BASH_SOURCE[0]}")/wsl-stage-init.sh" || exit 9
  fi
  need "$img" "stock ${name} 镜像"
  local mnt="$STAGE/mnt/stock_$name"
  mkdir -p "$mnt"
  if ! mountpoint -q "$mnt"; then
    mount -t erofs -o loop,ro "$img" "$mnt" || { echo "FATAL: 挂载 $img 失败"; exit 9; }
  fi
  need "$mnt/lib/modules" "stock ${name} 的 /lib/modules"
}

# 批量取 module_layout CRC，输出 "0x........" 每行一个
crc_of() { modprobe --dump-modversions "$1" 2>/dev/null | awk '$2=="module_layout"{print $1}'; }
