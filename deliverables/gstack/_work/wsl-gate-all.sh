#!/bin/bash
# 一条命令跑完：建模块集 → 三组实测。WSL 空闲会清 /root，必须一次跑完。
set -u
HERE="$(dirname "$0")"
bash "$HERE/wsl-gate-setup.sh" || { echo "SETUP FAILED"; exit 1; }
echo
bash "$HERE/wsl-gate-test.sh"
