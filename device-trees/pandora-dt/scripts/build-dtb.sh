#!/usr/bin/env bash
# 从 dts/ 源码可复现地构建 Xiaomi 17 Pro (pandora / canoe / SM8850) 设备树二进制
#
# 输出（build/ 下）：
#   canoe-base.dtb                    SoC 基础树（vendor_boot 内的 dtb）
#   overlays/board-pandora.dtbo       板级 overlay（dtbo 分区）
#   xiaomi-pandora.dtb                base + overlay 合并后的完整树
#   dtbo.img                          Android dt_table 镜像（dtbo 分区布局）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DTS="$ROOT/dts"
OUT="$ROOT/build"
OVOUT="$OUT/overlays"
LOG="$OUT/warnings.log"
: "${DTC:=dtc}"
: "${PAGE_SIZE:=4096}"

if ! command -v "$DTC" >/dev/null 2>&1; then
  echo "ERROR: dtc 未找到。安装 device-tree-compiler：" >&2
  echo "       sudo apt-get install device-tree-compiler" >&2
  echo "       或设置 DTC=/path/to/dtc" >&2
  exit 1
fi
echo "[build] dtc: $($DTC --version)"
mkdir -p "$OVOUT"
: > "$LOG"

compile() { # in out [extra dtc args...]
  local in="$1" out="$2"; shift 2
  echo "[build] $(basename "$in") -> $(basename "$out")"
  "$DTC" -I dts -O dtb -@ "$@" -o "$out" "$in" 2>>"$LOG" || {
    echo "  dtc FAILED，详见 $LOG"; tail -n 20 "$LOG"; exit 1; }
}

# 1) SoC 基础树（vendor_boot 内的 dtb，对应 Canoe v2）
compile "$DTS/xiaomi-pandora-common.dtsi" "$OUT/canoe-base.dtb"

# 2) 板级 overlay（dtbo 分区）
compile "$DTS/overlays/board-pandora-overlay.dts" "$OVOUT/board-pandora.dtbo"

# 3) 合并后的完整树
compile "$DTS/xiaomi-pandora.dts" "$OUT/xiaomi-pandora.dtb"

# 4) 打包成 dtbo.img
python3 "$ROOT/scripts/mkdtimage.py" create "$OUT/dtbo.img" \
  --page_size "$PAGE_SIZE" "$OVOUT/board-pandora.dtbo"

echo "[build] 完成，产物在 $OUT（警告见 $LOG）"
