#!/usr/bin/env bash
# 从原厂 OTA 与 PixelOS 整包里各自解出 dtbo / vendor_boot，拆成单棵 DTB /
# 单个 overlay entry，反编译成 dts，并生成 original/manifest.tsv 供入库。
#
# 体积约定：
#   WORK_DIR  放解出来的原始镜像（vendor_boot 100 MB / dtbo 23~32 MB），
#             默认 /root/work/dt-extract，**不要**落在 /mnt/c 上；
#   EXTRACT_DIR 只放拆出来的 dtb/dts（约 8 MB），默认仓库内 extracted/，
#             已被 .gitignore 忽略。
#
# 可覆盖变量：STOCK_OTA PIXELOS_ZIP LOS_DTBO WORK_DIR EXTRACT_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
TOOL="$ROOT/scripts/dttool.py"
: "${DTC:=dtc}"
: "${STOCK_OTA:=$REPO/pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip}"
: "${PIXELOS_ZIP:=$REPO/PixelOS_pandora-17.0-20261102/Fastboot_PixelOS_pandora-17.0-20261102-0424.zip}"
: "${LOS_DTBO:=/root/work/gstack/los_dtbo.img}"
: "${WORK_DIR:=/root/work/dt-extract}"
: "${EXTRACT_DIR:=$ROOT/extracted}"

for tool in "$DTC" python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: 未找到 $tool" >&2; exit 1; }
done
[ -f "$TOOL" ] || { echo "ERROR: 缺少 $TOOL" >&2; exit 1; }
[ -f "$REPO/tools/payload_dump.py" ] || { echo "ERROR: 缺少 tools/payload_dump.py" >&2; exit 1; }

mkdir -p "$WORK_DIR" "$EXTRACT_DIR" || {
  echo "ERROR: 无法创建 $WORK_DIR，可用 WORK_DIR=<可写目录> 覆盖" >&2; exit 1; }

echo "[extract] 工作目录 $WORK_DIR（剩余空间见下）"
df -h "$WORK_DIR" | tail -n 1

# 单个来源：解 → 拆 → 反编译
process_source() { # <标签> <vendor_boot.img> <dtbo.img>
  local label="$1" vb="$2" dtbo="$3"
  local out="$EXTRACT_DIR/$label"
  rm -rf "$out"; mkdir -p "$out/base" "$out/dtbo" "$out/dts"

  echo
  echo "[extract] == $label =="
  python3 "$TOOL" split-vb "$vb" "$out/base"
  python3 "$TOOL" split-dtbo "$dtbo" "$out/dtbo"

  local f
  for f in "$out/base"/*.dtb; do
    "$DTC" -I dtb -O dts -o "$out/dts/$(basename "${f%.dtb}").dts" "$f" 2>/dev/null
    python3 "$TOOL" normalize-dts --cells "$out/dts/$(basename "${f%.dtb}").dts" "$f"
  done
  for f in "$out/dtbo"/*.dtbo; do
    "$DTC" -I dtb -O dts -o "$out/dts/$(basename "${f%.dtbo}").dts" "$f" 2>/dev/null
    python3 "$TOOL" normalize-dts --cells "$out/dts/$(basename "${f%.dtbo}").dts" "$f"
  done
}

# 1) 原厂 OTA：只解 dtbo / vendor_boot 两个分区（整包 9 GB，全量解要很久）
[ -f "$STOCK_OTA" ] || { echo "ERROR: 找不到原厂 OTA $STOCK_OTA" >&2; exit 1; }
mkdir -p "$WORK_DIR/stock"
echo
echo "[extract] 原厂 OTA: $(basename "$STOCK_OTA")"
python3 "$REPO/tools/payload_dump.py" "$STOCK_OTA" "$WORK_DIR/stock" \
  dtbo vendor_boot --verify

# 2) PixelOS fastboot 包：只挑 dtbo.img / vendor_boot.img 两个成员
[ -f "$PIXELOS_ZIP" ] || { echo "ERROR: 找不到 PixelOS 包 $PIXELOS_ZIP" >&2; exit 1; }
mkdir -p "$WORK_DIR/pixelos"
echo
echo "[extract] PixelOS: $(basename "$PIXELOS_ZIP")"
python3 "$TOOL" unzip-parts "$PIXELOS_ZIP" "$WORK_DIR/pixelos" dtbo.img vendor_boot.img

process_source stock-a17 "$WORK_DIR/stock/vendor_boot.img" "$WORK_DIR/stock/dtbo.img"
process_source pixelos "$WORK_DIR/pixelos/vendor_boot.img" "$WORK_DIR/pixelos/dtbo.img"

# 原厂的 12 棵基础树与 2 个 overlay 是 make merge / make verify 的基准，
# 新克隆的仓库里可能缺失（*.dtb 默认不入库），这里按需补齐且绝不覆盖已有内容。
sync_fixture() { # <解出的文件> <仓库内路径>
  if [ ! -f "$2" ]; then
    cp "$1" "$2"; echo "  [补齐] ${2#$ROOT/}"
  elif ! cmp -s "$1" "$2"; then
    echo "  [警告] ${2#$ROOT/} 与本次解包结果不一致，保留原文件" >&2
  fi
}
echo
echo "[extract] 校准 original/ 基准文件"
mkdir -p "$ROOT/original/base-parts" "$ROOT/original/dtbo-parts"
for f in "$EXTRACT_DIR/stock-a17/base"/*.dtb; do
  sync_fixture "$f" "$ROOT/original/base-parts/$(basename "$f")"
done
for f in "$EXTRACT_DIR/stock-a17/dtbo"/*.dtbo; do
  sync_fixture "$f" "$ROOT/original/dtbo-parts/$(basename "$f")"
done
echo "  基准文件齐全"

# 3) LOS 只有 dtbo.img，单独列进清单
MANIFEST_ARGS=(
  "stock-a17=$WORK_DIR/stock/vendor_boot.img"
  "stock-a17=$WORK_DIR/stock/dtbo.img"
  "pixelos=$WORK_DIR/pixelos/vendor_boot.img"
  "pixelos=$WORK_DIR/pixelos/dtbo.img"
)
if [ -f "$LOS_DTBO" ]; then
  mkdir -p "$EXTRACT_DIR/los"; rm -rf "$EXTRACT_DIR/los/dtbo"
  python3 "$TOOL" split-dtbo "$LOS_DTBO" "$EXTRACT_DIR/los/dtbo"
  MANIFEST_ARGS+=("los=$LOS_DTBO")
else
  echo "[extract] 跳过 LOS（$LOS_DTBO 不存在）"
fi

echo
python3 "$TOOL" manifest "$ROOT/original/manifest.tsv" "${MANIFEST_ARGS[@]}"

echo
echo "[extract] 完成，产物在 $EXTRACT_DIR（已 gitignore），清单 $ROOT/original/manifest.tsv"
