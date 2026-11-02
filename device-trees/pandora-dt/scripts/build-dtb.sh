#!/usr/bin/env bash
# 从 dts/ 源码可复现地构建 Xiaomi 17 Pro (pandora / canoe / SM8850) 设备树二进制
#
# 输出（build/ 下）：
#   canoe-base.dtb                    SoC 基础树（vendor_boot 内的 dtb）
#   overlays/board-pandora-alt.dtbo   原厂 dtbo entry[0]（45 个 fragment）
#   overlays/board-pandora.dtbo       原厂 dtbo entry[1]（145 个 fragment，主用）
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
# dtbo.img 每个 entry 的 id/rev/custom[4]；原厂两份 overlay 都是 0/0/0/0/0/0/0，
# 但引导器按这套元数据挑 overlay，所以必须可覆盖而不是写死。
: "${DTBO_META0:=0,0,0,0,0,0}"
: "${DTBO_META1:=0,0,0,0,0,0}"

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

# 2) 板级 overlay（dtbo 分区的两个 entry，顺序与原厂 dtbo.img 一致）
compile "$DTS/overlays/board-pandora-overlay-alt.dts" "$OVOUT/board-pandora-alt.dtbo"
compile "$DTS/overlays/board-pandora-overlay.dts" "$OVOUT/board-pandora.dtbo"

# 3) 合并后的完整树（人工整理的 base+overlay 结果，供阅读与交叉校验）
compile "$DTS/xiaomi-pandora.dts" "$OUT/xiaomi-pandora.dtb"

# 4) 打包成 dtbo.img：原厂是紧凑布局（首个 entry 在 0x60），不是页对齐
python3 "$ROOT/scripts/mkdtimage.py" create "$OUT/dtbo.img" \
  --page_size "$PAGE_SIZE" --packed \
  --meta "$DTBO_META0" --meta "$DTBO_META1" \
  "$OVOUT/board-pandora-alt.dtbo" "$OVOUT/board-pandora.dtbo"

echo "[build] 完成，产物在 $OUT（警告见 $LOG）"
