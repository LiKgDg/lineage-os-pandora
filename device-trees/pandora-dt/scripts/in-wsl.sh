#!/usr/bin/env bash
# 在「有 dtc 的环境」里执行给定命令。
#
# Windows 的 Git Bash 没有 device-tree-compiler，因此当本机找不到 dtc /
# fdtoverlay 而存在 wsl.exe 时，把命令连同当前工作目录翻译到 WSL 里执行；
# 本机已有工具链（Linux / macOS / 装了 dtc.exe）则直接执行。
set -euo pipefail

if command -v dtc >/dev/null 2>&1 && command -v fdtoverlay >/dev/null 2>&1; then
  exec "$@"
fi
if ! command -v wsl.exe >/dev/null 2>&1; then
  echo "ERROR: 未找到 dtc/fdtoverlay，也没有可用的 wsl.exe" >&2
  echo "       安装 device-tree-compiler，或设置 DTC=/path/to/dtc" >&2
  exit 1
fi

here="$(pwd)"
win="$(cygpath -w "$here" 2>/dev/null || printf '%s' "$here")"
wpath="$(wsl.exe -u root -e wslpath -a -u "$win" | tr -d '\r')"

# 白名单转发，避免在 WSL 里丢失调用方指定的路径/参数
forward=()
for name in DTC PAGE_SIZE STOCK_OTA PIXELOS_ZIP LOS_DTBO WORK_DIR EXTRACT_DIR \
            BASE OVERLAY STOCK_DTBO PIXELOS_DTBO; do
  [ -n "${!name:-}" ] && forward+=("$name=${!name}")
done

cmd=""
if [ "${#forward[@]}" -gt 0 ]; then
  cmd="env "
  for pair in "${forward[@]}"; do printf -v q '%q' "$pair"; cmd+="$q "; done
fi
for arg in "$@"; do printf -v q '%q' "$arg"; cmd+="$q "; done
printf -v cdq '%q' "$wpath"

exec wsl.exe -u root -e bash -lc "cd $cdq && $cmd"
