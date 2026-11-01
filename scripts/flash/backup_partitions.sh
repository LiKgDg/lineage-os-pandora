#!/bin/bash
# 备份 pandora 关键分区到 PC
set -u
ADB="./platform-tools/adb.exe"
DST="/d/WSL/out/pandora/backup"
mkdir -p "$DST"

PARTS="boot_a init_boot_a recovery_a vendor_boot_a dtbo_a vbmeta_a vbmeta_system_a"

echo "=== 备份到 $DST ==="
printf "%-20s %12s %12s  %s\n" "分区" "分区大小" "已备份" "sha256(前16)"

FAIL=0
for p in $PARTS; do
    size=$($ADB shell "blockdev --getsize64 /dev/block/by-name/$p 2>/dev/null" 2>/dev/null | tr -d '\r\n ')
    if [ -z "$size" ] || [ "$size" = "0" ]; then
        printf "%-20s %12s\n" "$p" "读取失败"
        FAIL=$((FAIL+1))
        continue
    fi
    $ADB exec-out "dd if=/dev/block/by-name/$p bs=1048576 2>/dev/null" > "$DST/$p.img" 2>/dev/null
    got=$(stat -c %s "$DST/$p.img" 2>/dev/null || echo 0)
    sha=$(sha256sum "$DST/$p.img" 2>/dev/null | cut -c1-16)
    if [ "$got" = "$size" ]; then
        printf "%-20s %12s %12s  %s\n" "$p" "$size" "$got" "$sha"
    else
        printf "%-20s %12s %12s  %s  <-- 大小不符\n" "$p" "$size" "$got" "$sha"
        FAIL=$((FAIL+1))
    fi
done

echo
echo "=== 汇总 ==="
ls -la "$DST" | tail -n +2 | awk '{printf "%-28s %s 字节\n", $9, $5}'
echo "失败项: $FAIL"
du -sh "$DST" 2>/dev/null | awk '{print "备份总大小: " $1}'
