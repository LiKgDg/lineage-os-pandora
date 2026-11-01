#!/bin/bash
# 用 A17 (OS4.0.5.0) blobs 重建 vendor/xiaomi/sm8850-common
# 必须在单个 WSL 会话内完成，否则 loop 挂载会随 WSL 空闲关闭而丢失
set -e
M=/mnt/os405
ST=/root/stage
BK=/root/backup-sm8850-a16/proprietary
OUT=/root/los24/vendor/xiaomi/sm8850-common
TOOLS="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/tools"

echo "=== [1/6] 挂载 A17 镜像 ==="
for p in vendor odm system_ext product system; do
    mkdir -p "$M/$p"
    mountpoint -q "$M/$p" || mount -o loop,ro "/root/os405/$p.img" "$M/$p"
done
echo "  ok"

echo
echo "=== [2/6] 构建 staging（vendor 全量 + odm 排除相机）==="
rm -rf "$ST"
mkdir -p "$ST"

echo "  vendor ..."
cp -a "$M/vendor" "$ST/vendor"

echo "  odm ..."
cp -a "$M/odm" "$ST/odm"
rm -rf "$ST/odm/etc/camera"
rm -f "$ST"/odm/lib64/libarcsoft_*.so
echo "  odm 体积: $(du -sh "$ST/odm" | cut -f1)"

echo
echo "=== [3/6] system_ext / product / system 按 A16 清单更新 ==="
for p in system_ext product; do
    mkdir -p "$ST/$p"
    n=0; miss=0
    while IFS= read -r f; do
        rel="${f#$BK/$p/}"
        src="$M/$p/$rel"
        if [ -e "$src" ]; then
            mkdir -p "$ST/$p/$(dirname "$rel")"
            cp -a "$src" "$ST/$p/$rel"
            n=$((n+1))
        else
            miss=$((miss+1))
        fi
    done < <(find "$BK/$p" -type f ! -name "*.link" 2>/dev/null)
    echo "  $p: 更新 $n 个, A17 中缺失 $miss 个"
done

# system 是嵌套布局，有效根在 $M/system/system
mkdir -p "$ST/system"
n=0; miss=0
while IFS= read -r f; do
    rel="${f#$BK/system/}"
    src="$M/system/system/$rel"
    if [ -e "$src" ]; then
        mkdir -p "$ST/system/$(dirname "$rel")"
        cp -a "$src" "$ST/system/$rel"
        n=$((n+1))
    else
        miss=$((miss+1))
        echo "    缺失: $rel"
    fi
done < <(find "$BK/system" -type f ! -name "*.link" 2>/dev/null)
echo "  system: 更新 $n 个, 缺失 $miss 个"

echo
echo "=== [4/6] staging 汇总 ==="
du -sh "$ST"/* 2>/dev/null
echo -n "  总文件数: "; find "$ST" -type f | wc -l
echo -n "  总体积: "; du -sh "$ST" | cut -f1

echo
echo "=== [5/6] 生成 blob 包 ==="
rm -rf "$OUT/proprietary"
python3 "$TOOLS/gen_blob_list.py" "$OUT" \
    "vendor=$ST/vendor" \
    "odm=$ST/odm" \
    "system_ext=$ST/system_ext" \
    "product=$ST/product" \
    "system=$ST/system" 2>&1 | tail -12

echo
echo "=== [6/6] 生成 Android.bp ==="
python3 "$TOOLS/gen_vendor_bp.py" "$OUT" 2>&1 | tail -8

echo
echo "=== 完成 ==="
du -sh "$OUT" 2>/dev/null
echo -n "proprietary-files.txt 条目: "; wc -l < "$OUT/proprietary-files.txt" 2>/dev/null
