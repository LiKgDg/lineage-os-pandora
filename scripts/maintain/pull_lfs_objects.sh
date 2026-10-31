#!/bin/bash
# 拉取源码树里所有 Git LFS 对象。
#
# 背景：repo sync 默认不下载 LFS 对象，仓库里只留 134 字节的指针文件，
# 例如 external/chromium-webview/prebuilt/*/webview.apk。
# 构建时会报 "failed opening zip: Invalid file"。
#
# 用法:
#   pull_lfs_objects.sh            # 扫描并拉取全部
#   pull_lfs_objects.sh --check    # 只扫描报告，不下载
#
# 代理：默认走 127.0.0.1:7890，可用 LFS_PROXY 覆盖
set -u

TOP=${TOP:-/root/los24}
PROXY=${LFS_PROXY:-http://127.0.0.1:7890}
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

export http_proxy=$PROXY https_proxy=$PROXY HTTP_PROXY=$PROXY HTTPS_PROXY=$PROXY

echo "=== 查找使用 LFS 的项目 ==="
mapfile -t PROJECTS < <(
    find "$TOP" -name ".gitattributes" -not -path "$TOP/out/*" -not -path "*/.repo/*" 2>/dev/null \
    | while read -r f; do
        if grep -q "filter=lfs" "$f" 2>/dev/null; then
            dirname "$f"
        fi
    done | sort -u
)

if [ ${#PROJECTS[@]} -eq 0 ]; then
    echo "未发现使用 LFS 的项目"
    exit 0
fi
printf '  %s\n' "${PROJECTS[@]}"
echo

fail=0
for d in "${PROJECTS[@]}"; do
    echo "=== ${d#$TOP/} ==="
    cd "$d" || { echo "  无法进入"; continue; }

    # 统计指针文件
    ptr=$(find . -maxdepth 2 -type f \( -name "*.apk" -o -name "*.jar" -o -name "*.zip" -o -name "*.so" \) \
          -size -1k 2>/dev/null | while read -r x; do
              head -c 100 "$x" 2>/dev/null | grep -q "git-lfs.github.com/spec/v1" && echo "$x"
          done | wc -l)
    echo "  指针文件: $ptr 个"

    if [ "$CHECK_ONLY" -eq 1 ]; then
        continue
    fi
    if [ "$ptr" -eq 0 ]; then
        echo "  无需拉取"
        continue
    fi

    git lfs install --local >/dev/null 2>&1
    if timeout 1800 git lfs pull 2>&1 | tail -3; then
        after=$(find . -maxdepth 2 -type f \( -name "*.apk" -o -name "*.jar" -o -name "*.zip" -o -name "*.so" \) \
                -size -1k 2>/dev/null | while read -r x; do
                    head -c 100 "$x" 2>/dev/null | grep -q "git-lfs.github.com/spec/v1" && echo "$x"
                done | wc -l)
        echo "  拉取后剩余指针: $after 个"
        [ "$after" -gt 0 ] && fail=$((fail+1))
    else
        echo "  拉取失败"
        fail=$((fail+1))
    fi
    echo
done

echo "=== 汇总: $fail 个项目未完成 ==="
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
