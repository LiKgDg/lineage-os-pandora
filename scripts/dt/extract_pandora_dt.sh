#!/bin/bash
# extract_pandora_dt.sh —— 从原厂 boot/vendor_boot/dtbo 提取设备树（pandora-dt 的早期版本）
set -e
W=/root/pandora-dt
UB=/root/los24/system/tools/mkbootimg/unpack_bootimg.py
STOCK=/mnt/d/WSL/out/pandora/stock-a17

rm -rf "$W"; mkdir -p "$W"/{original,dts/overlays,scripts,docs,build}

echo "=== 1. 解包 vendor_boot 取 base dtb ==="
python3 "$UB" --boot_img "$STOCK/vendor_boot.img" --out "$W/vb" >/dev/null 2>&1
cp "$W/vb/dtb" "$W/original/stock-base-blob.dtb"
cp "$W/vb/bootconfig" "$W/original/stock-bootconfig.txt"
echo "  dtb blob: $(stat -c %s "$W/original/stock-base-blob.dtb") 字节"

echo
echo "=== 2. 拆分拼接的 dtb ==="
python3 "/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain/split_dtb.py" \
    "$W/original/stock-base-blob.dtb" "$W/original/base-parts" 2>&1 | head -20
ls "$W/original/base-parts" | wc -l

echo
echo "=== 3. 复制 dtbo.img ==="
cp "$STOCK/dtbo.img" "$W/original/stock-dtbo.img"
echo "  dtbo.img: $(stat -c %s "$W/original/stock-dtbo.img") 字节"

echo
echo "=== 4. 解析 dtbo 表 ==="
python3 - "$W/original/stock-dtbo.img" "$W/original/dtbo-parts" <<'PY'
import struct, sys, os
d = open(sys.argv[1], "rb").read()
magic, total, hdr_sz, ent_sz, ent_cnt, ent_off, page_sz, ver = struct.unpack_from(">8I", d, 0)
print("  magic=0x%08x entries=%d page=%d ver=%d" % (magic, ent_cnt, page_sz, ver))
os.makedirs(sys.argv[2], exist_ok=True)
for i in range(ent_cnt):
    o = ent_off + i * ent_sz
    sz, off, *_ = struct.unpack_from(">8I", d, o)
    out = os.path.join(sys.argv[2], "%02d.dtbo" % i)
    open(out, "wb").write(d[off:off+sz])
    print("    [%02d] %d 字节" % (i, sz))
PY

echo
echo "=== 5. 各 dtb/dtbo 的 model ==="
for f in "$W"/original/base-parts/*.dtb "$W"/original/dtbo-parts/*.dtbo; do
    [ -f "$f" ] || continue
    m=$(fdtget "$f" / model 2>/dev/null || echo "?")
    printf "  %-30s %s\n" "$(basename "$f")" "$m"
done
