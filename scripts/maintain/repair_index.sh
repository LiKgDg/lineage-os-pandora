#!/bin/bash
# 修复索引被清空的项目：git reset --hard HEAD
# 只处理「HEAD 有内容但索引为空」的项目，避免误伤空仓库。
cd /root/los24 || exit 1
DRY=${1:-}

PROJS="external/deqp
external/rust/autocxx
hardware/telink/atv/refDesignRcu
packages/apps/Car/DriverUIPrebuilt
packages/apps/Car/RotaryImePrebuilt
packages/modules/desktop/Serviceability
prebuilts/module_sdk/NpuManager
prebuilts/module_sdk/WebViewBootstrap"

echo "$PROJS" | while read -r p; do
    [ -n "$p" ] || continue
    [ -d "$p/.git" ] || { echo "SKIP $p（非 git）"; continue; }

    n_head=$(git -C "$p" ls-tree -r HEAD --name-only 2>/dev/null | wc -l)
    n_idx=$(git -C "$p" ls-files 2>/dev/null | wc -l)
    n_disk=$(find "$p" -type f -not -path "*/.git/*" 2>/dev/null | wc -l)

    if [ "$n_head" -eq 0 ]; then
        echo "SKIP $p（HEAD 为空仓库）"
        continue
    fi
    if [ "$n_idx" -ne 0 ]; then
        echo "SKIP $p（索引正常，$n_idx 项）"
        continue
    fi

    if [ "$DRY" = "--dry-run" ]; then
        echo "WOULD  $p  HEAD=$n_head disk=$n_disk"
    else
        git -C "$p" reset --hard HEAD >/dev/null 2>&1
        rc=$?
        n_after=$(git -C "$p" ls-files 2>/dev/null | wc -l)
        echo "FIXED $p  rc=$rc  索引 $n_idx -> $n_after  (HEAD=$n_head)"
    fi
done
