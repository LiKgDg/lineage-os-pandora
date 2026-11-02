#!/bin/bash
# 提取内核段并验证门禁的 -K/--kernel banner 校验能抓到「内核换了、模块没换」。
set -u
source "$(dirname "$0")/wsl-common.sh"

K="$STAGE/los_kernel.bin"
if [ ! -f "$K" ]; then
  echo "== 从 boot.img 提取 kernel 段 =="
  python3 - "$IMGS/boot.img" "$K" "$WORK" <<'PY'
import sys
sys.path.insert(0, sys.argv[3])
from bootimg import parse_boot
info = parse_boot(sys.argv[1])
with open(sys.argv[1], "rb") as f:
    f.seek(info["kernel_off"]); k = f.read(info["kernel_size"])
open(sys.argv[2], "wb").write(k)
print(f"   kernel {len(k)} bytes")
PY
fi
need "$K" "LOS kernel"

echo
echo "== kernel banner =="
strings "$K" | grep -m1 "^Linux version"

echo
echo "== 门禁：LOS vendor_boot + -K 内核 banner 校验（期望 FAIL）=="
bash "$WORK/kmi-gate.sh" -q -K "$K" "$STAGE/vb/los/lib/modules" || echo "  (exit=$? 符合预期)"

echo
echo "== 门禁：stock vendor_boot + -K（期望 PASS）=="
bash "$WORK/kmi-gate.sh" -q -K "$K" "$STAGE/vb/stock/lib/modules" || echo "  (exit=$? )"
