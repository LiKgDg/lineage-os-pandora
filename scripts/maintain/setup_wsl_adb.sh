#!/bin/bash
# 在 WSL 内安装 adb 并指向 Windows 的 adb server（镜像网络模式，走回环地址）
set -e

echo "=== 安装 adb ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>&1 | tail -2
apt-get install -y -qq adb 2>&1 | tail -3
which adb && adb version | head -1

echo "=== 写入 ADB_SERVER_SOCKET ==="
LINE='export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037'
if ! grep -q "ADB_SERVER_SOCKET" "$HOME/.bashrc" 2>/dev/null; then
  echo "" >> "$HOME/.bashrc"
  echo "# 复用 Windows 侧 adb server（WSL networkingMode=Mirrored）" >> "$HOME/.bashrc"
  echo "$LINE" >> "$HOME/.bashrc"
  echo "已写入 ~/.bashrc"
else
  echo "已存在，跳过"
fi

echo "=== 当前会话生效并验证 ==="
export ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
sleep 2
adb devices 2>&1
