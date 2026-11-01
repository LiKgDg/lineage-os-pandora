#!/bin/bash
# 保持 A16 的文件选择范围，二进制替换为 A17 版本
set -e
M=/mnt/os405
ST=/root/stage2
BK=/root/backup-sm8850-a16/proprietary
OUT=/root/los24/vendor/xiaomi/sm8850-common
TOOLS="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/tools"
S="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/scripts/maintain"

echo "=== [1/5] 挂载 A17 镜像 ==="
for p in vendor odm system_ext product system; do
    mkdir -p "$M/$p"
    mountpoint -q "$M/$p" || mount -o loop,ro "/root/os405/$p.img" "$M/$p"
done
echo "  ok"

echo
echo "=== [2/5] 按 A16 清单构建 staging（A17 优先）==="
rm -rf "$ST"; mkdir -p "$ST"
total=0; from_a17=0; from_a16=0
for part in vendor odm system_ext product system; do
    base="$BK/$part"
    [ -d "$base" ] || continue
    p17=0; p16=0
    while IFS= read -r f; do
        rel="${f#$base/}"
        dst="$ST/$part/$rel"
        mkdir -p "$(dirname "$dst")"
        # system 分区是嵌套布局
        if [ "$part" = "system" ] && [ -e "$M/system/system/$rel" ]; then
            cp -a "$M/system/system/$rel" "$dst"; p17=$((p17+1))
        elif [ "$part" != "system" ] && [ -e "$M/$part/$rel" ]; then
            cp -a "$M/$part/$rel" "$dst"; p17=$((p17+1))
        else
            cp -a "$f" "$dst"; p16=$((p16+1))
        fi
    done < <(find "$base" -type f ! -name "*.link" 2>/dev/null)
    # 保留符号链接
    while IFS= read -r f; do
        rel="${f#$base/}"; rel="${rel%.link}"
        mkdir -p "$(dirname "$ST/$part/$rel")"
        ln -sf "$(cat "$f")" "$ST/$part/$rel" 2>/dev/null || true
    done < <(find "$base" -type f -name "*.link" 2>/dev/null)
    echo "  $part: A17 $p17 个, 沿用 A16 $p16 个"
    total=$((total+p17+p16)); from_a17=$((from_a17+p17)); from_a16=$((from_a16+p16))
done
echo "  合计 $total 个（A17: $from_a17, A16: $from_a16）"

echo
echo "=== [3/5] 生成 blob 包 ==="
rm -rf "$OUT/proprietary"
python3 "$TOOLS/gen_blob_list.py" "$OUT" \
    "vendor=$ST/vendor" "odm=$ST/odm" "system_ext=$ST/system_ext" \
    "product=$ST/product" "system=$ST/system" 2>&1 | tail -10

echo
echo "=== [4/5] 生成 Android.bp ==="
python3 "$TOOLS/gen_vendor_bp.py" "$OUT" 2>&1 | tail -3

echo
echo "=== [5/5] 补 rildb filegroup ==="
python3 "$S/fix_rildb_filegroups.py" 2>&1 | tail -3

echo
echo "=== 完成 ==="
du -sh "$OUT" | cut -f1
echo -n "条目: "; wc -l < "$OUT/proprietary-files.txt"
