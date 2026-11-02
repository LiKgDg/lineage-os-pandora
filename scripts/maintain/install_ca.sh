#!/bin/bash
# install_ca.sh —— 把 staging 里的自定义 CA 证书转换并安装进系统信任库
set -e
S="/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/staging"
echo "=== 文件 ==="
ls -la "$S"/steamtools-*.cer
file "$S/steamtools-1.cer"

echo "=== 转换并安装 ==="
for i in 1 2; do
  src="$S/steamtools-$i.cer"
  dst="/usr/local/share/ca-certificates/steamtools-$i.crt"
  if openssl x509 -in "$src" -inform DER -out "$dst" 2>/dev/null; then
    echo "installed $i (DER)"
  elif openssl x509 -in "$src" -out "$dst" 2>/dev/null; then
    echo "installed $i (PEM)"
  else
    echo "FAILED $i"
  fi
done

update-ca-certificates 2>&1 | tail -3

echo "=== 验证 github ==="
curl -sS -o /dev/null -w "github: %{http_code} %{time_total}s\n" https://github.com 2>&1 || true
echo "=== git 验证 ==="
timeout 30 git ls-remote https://github.com/TWRP-Test/android_cts twrp-16.0 2>&1 | head -2
