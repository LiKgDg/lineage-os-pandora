#!/bin/bash
# 清理可再生的临时产物（不涉及 out/ 与备份）
echo "=== 删除前 ==="
df -h / | tail -1

TARGETS=(
  /root/os405
  /root/stage
  /root/stage2
  /root/a17kernel
  /root/pandora-kernel-staging
  /tmp/vr
  /tmp/vd
  /tmp/sd
  /tmp/vfy
  /tmp/ota_list
  /tmp/vr.cpio
)

TOTAL=0
for d in "${TARGETS[@]}"; do
    if [ -e "$d" ]; then
        sz=$(du -sm "$d" 2>/dev/null | cut -f1)
        TOTAL=$((TOTAL+sz))
        rm -rf "$d"
        echo "  已删 $d (${sz} MB)"
    fi
done

echo
echo "=== 清理构建日志 ==="
for f in /root/d3.log /root/d5.log /root/siso*.log* ; do
    [ -f "$f" ] || continue
    sz=$(du -sm "$f" 2>/dev/null | cut -f1)
    TOTAL=$((TOTAL+sz))
    rm -f "$f"
    echo "  已删 $f (${sz} MB)"
done

echo
echo "=== out 目录下的 siso 日志 ==="
find /root/los24/out -maxdepth 1 -name "siso*.log*" -size +10M -print -delete 2>/dev/null | while read -r f; do
    echo "  已删 $f"
done

echo
echo "=== 删除后 ==="
df -h / | tail -1
echo "本次释放约 ${TOTAL} MB"
