#!/usr/bin/env bash
# 重建并与原厂二进制做三层校验，任一 FAIL 即非 0 退出。
#
#   (a) 根节点属性逐项对照：把 `/` 上的**所有**属性枚举出来逐字节比，
#       覆盖 base / overlay / 合并运行时树三组配对；
#   (b) dtbo.img entry 元数据逐项对照：magic/version/page_size/entry_count
#       以及每个 entry 的 id/rev/custom[0..3]/dtb_size；
#   (c) 三来源（原厂 A17 / PixelOS / LOS）dtbo 差异矩阵。
#
# 旧版本只比 model 与 compatible 四个字符串，因此漏掉了 135 处属性值差异
# （dtc 反编译把「NUL 后紧跟数字」的字符串列表写成了歧义转义）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
TOOL="$ROOT/scripts/dttool.py"
B="$ROOT/build"
O="$ROOT/original"
: "${WORK_DIR:=/root/work/dt-extract}"
: "${PIXELOS_DTBO:=$REPO/PixelOS_pandora-17.0-20261102/dtbo.img}"
: "${LOS_DTBO:=/root/work/gstack/los_dtbo.img}"
: "${STOCK_DTBO:=$WORK_DIR/stock/dtbo.img}"
: "${BASE:=$O/base-parts/02_dtb_581424.dtb}"
: "${OVERLAY:=$O/dtbo-parts/01.dtbo}"

cd "$ROOT"
ok=0
bad=0
failed=()

block() { # <显示名> <命令...>
  local name="$1"; shift
  echo
  echo "──────────── $name ────────────"
  if "$@"; then
    ok=$((ok + 1))
  else
    bad=$((bad + 1)); failed+=("$name")
  fi
}

echo "== 重建 dts 产物 =="
bash scripts/build-dtb.sh >/dev/null
echo "  build/ 已刷新"

block "合并（fdtoverlay）+ 结构对账" bash scripts/merge-dtb.sh

block "根节点属性：原厂 base vs 重建 base" \
  python3 "$TOOL" verify-root "$BASE" "$B/canoe-base.dtb" --label "base / Canoe v2"

block "根节点属性：原厂 overlay vs 重建 overlay" \
  python3 "$TOOL" verify-root "$OVERLAY" "$B/overlays/board-pandora.dtbo" --label "overlay / dtbo entry[1]"

block "根节点属性：原厂合并运行时树 vs 重建合并树" \
  python3 "$TOOL" verify-root "$B/runtime.dtb" "$B/xiaomi-pandora.dtb" --label "runtime"

echo
if [ -f "$STOCK_DTBO" ]; then
  echo "  （对比基准：原厂 A17 dtbo.img，$(stat -c%s "$STOCK_DTBO") 字节，"
  echo "    sha256 $(sha256sum "$STOCK_DTBO" | cut -c1-16)）"
  block "dtbo.img 元数据：原厂 A17 vs 重建" \
    python3 "$TOOL" verify-img "$STOCK_DTBO" "$B/dtbo.img"
else
  echo "  SKIP：未找到 $STOCK_DTBO（先跑 make extract）"
fi

echo
if [ -f "$PIXELOS_DTBO" ]; then
  echo "  （对比基准：PixelOS dtbo.img，$(stat -c%s "$PIXELOS_DTBO") 字节，"
  echo "    sha256 $(sha256sum "$PIXELOS_DTBO" | cut -c1-16)）"
  block "dtbo.img 元数据：PixelOS vs 重建" \
    python3 "$TOOL" verify-img "$PIXELOS_DTBO" "$B/dtbo.img"
else
  echo "  SKIP：未找到 $PIXELOS_DTBO"
fi

echo
echo "──────────── 三来源差异矩阵 ────────────"
matrix_args=()
[ -f "$STOCK_DTBO" ] && matrix_args+=("stock-a17=$STOCK_DTBO")
[ -f "$PIXELOS_DTBO" ] && matrix_args+=("pixelos=$PIXELOS_DTBO")
[ -f "$LOS_DTBO" ] && matrix_args+=("los=$LOS_DTBO")
if [ "${#matrix_args[@]}" -lt 2 ]; then
  echo "  SKIP：可用来源少于 2 个"
else
  block "三来源差异矩阵" python3 "$TOOL" matrix "${matrix_args[@]}"
fi

echo
echo "=========================================="
echo "PASS $ok  FAIL $bad"
if [ "$bad" -ne 0 ]; then
  printf '  FAIL: %s\n' "${failed[@]}"
  echo "=========================================="
  exit 1
fi
echo "=========================================="
