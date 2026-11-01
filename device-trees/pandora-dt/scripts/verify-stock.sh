#!/usr/bin/env bash
# 重新构建并与原厂二进制对照根节点元数据，证明 dts 能还原设备运行时设备树
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
bash scripts/build-dtb.sh >/dev/null
B="$ROOT/build"; O="$ROOT/original"

pass=0; fail=0
check() { # 标签 原厂值 构建值
  local label="$1" s="$2" b="$3"
  if [ "$s" == "$b" ]; then
    echo "PASS  $label = $b"; pass=$((pass+1))
  else
    echo "FAIL  $label"; echo "      原厂: $s"; echo "      构建: $b"; fail=$((fail+1))
  fi
}

echo "== 基础树（Canoe v2）=="
check "model"      "$(fdtget "$O/base-parts/02_dtb_581424.dtb" / model 2>/dev/null)" \
                    "$(fdtget "$B/canoe-base.dtb" / model 2>/dev/null)"
check "compatible" "$(fdtget "$O/base-parts/02_dtb_581424.dtb" / compatible 2>/dev/null)" \
                    "$(fdtget "$B/canoe-base.dtb" / compatible 2>/dev/null)"

echo
echo "== 板级 overlay =="
check "model"      "$(fdtget "$O/dtbo-parts/01.dtbo" / model 2>/dev/null)" \
                    "$(fdtget "$B/overlays/board-pandora.dtbo" / model 2>/dev/null)"
check "compatible" "$(fdtget "$O/dtbo-parts/01.dtbo" / compatible 2>/dev/null | tr '\0' ' ')" \
                    "$(fdtget "$B/overlays/board-pandora.dtbo" / compatible 2>/dev/null | tr '\0' ' ')"

echo
echo "== 合并完整树 =="
echo "  model      = $(fdtget "$B/xiaomi-pandora.dtb" / model 2>/dev/null)"
echo "  compatible = $(fdtget "$B/xiaomi-pandora.dtb" / compatible 2>/dev/null | tr '\0' ' ')"

echo
echo "== dtbo.img =="
python3 - "$B/dtbo.img" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
magic, total, hdr, esz, cnt, off, page, ver = struct.unpack_from(">8I", d, 0)
print("  magic=0x%08x entries=%d page=%d size=%d" % (magic, cnt, page, len(d)))
PY

echo
echo "=========================================="
echo "PASS $pass  FAIL $fail"
echo "=========================================="
[ "$fail" -eq 0 ] || exit 1
