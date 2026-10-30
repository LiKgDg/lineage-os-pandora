#!/bin/bash
# 列出 manifest 中声明但工作区不存在的项目路径。
# 用法：bash find_missing_projects.sh [/root/twrp]
ROOT="${1:-/root/twrp}"
cd "$ROOT" || exit 9

REPO=/root/repo-tool/repo
[ -x "$REPO" ] || REPO=.repo/repo/repo

total=0
missing=0
while IFS= read -r p; do
  total=$((total + 1))
  if [ ! -e "$p" ]; then
    echo "MISS $p"
    missing=$((missing + 1))
  fi
done < <("$REPO" list -p 2>/dev/null)

echo "----"
echo "项目总数: $total"
echo "缺失: $missing"
