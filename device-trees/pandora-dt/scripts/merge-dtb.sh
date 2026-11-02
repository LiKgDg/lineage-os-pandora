#!/usr/bin/env bash
# 用上游 fdtoverlay 做真实的 base dtb + 板级 overlay 合并，再与 dts/ 人工整理
# 的合并树做结构对账。
#
#   fdtoverlay -i <base.dtb> -o build/runtime.dtb <overlay.dtbo>
#   dtc -I dtb -O dts build/runtime.dtb -o build/runtime.dts
#
# 对账口径：节点数、属性数、排序后的节点路径集合、以及每个节点上每个属性的
# 原始字节都必须一致——只看 model/compatible 会漏掉 135 处属性值差异（见
# docs/dt-rebuild-report.md）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build"
: "${DTC:=dtc}"
: "${FDT_OVERLAY:=fdtoverlay}"
: "${BASE:=$ROOT/original/base-parts/02_dtb_581424.dtb}"
: "${OVERLAY:=$ROOT/original/dtbo-parts/01.dtbo}"

for tool in "$DTC" "$FDT_OVERLAY"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: 未找到 $tool（device-tree-compiler 提供）" >&2
    exit 1
  fi
done
for f in "$BASE" "$OVERLAY"; do
  [ -f "$f" ] || { echo "ERROR: 缺少输入 $f（先跑 make extract）" >&2; exit 1; }
done

mkdir -p "$OUT"
echo "[merge] base    = ${BASE#$ROOT/}"
echo "[merge] overlay = ${OVERLAY#$ROOT/}"
"$FDT_OVERLAY" -i "$BASE" -o "$OUT/runtime.dtb" "$OVERLAY"
"$DTC" -I dtb -O dts -o "$OUT/runtime.dts" "$OUT/runtime.dtb"
echo "[merge] 产物: build/runtime.dtb ($(stat -c%s "$OUT/runtime.dtb") 字节)、build/runtime.dts"

echo
echo "[merge] 与 build/xiaomi-pandora.dtb 结构对账"
if [ ! -f "$OUT/xiaomi-pandora.dtb" ]; then
  echo "ERROR: 缺少 build/xiaomi-pandora.dtb，先跑 make dtb" >&2
  exit 1
fi
python3 "$ROOT/scripts/dttool.py" cmp "$OUT/xiaomi-pandora.dtb" "$OUT/runtime.dtb"
