#!/bin/bash
# 回收 Ubuntu 磁盘空间：移除构建不需要的 CTS、临时目录与缓存。
set -e
ROOT=/root/twrp

echo "=== 清理前 ==="
df -h / | tail -1

# 1. CTS 与 recovery 构建无关（约 15 GB），并从 manifest 中移除避免重新拉取
if [ -f "$ROOT/.repo/local_manifests/pinned.xml" ]; then
  if ! grep -q "remove-project.*android_cts" "$ROOT/.repo/local_manifests/pinned.xml"; then
    python3 - <<'PY'
p = "/root/twrp/.repo/local_manifests/pinned.xml"
s = open(p, encoding="utf-8").read()
add = '  <remove-project name="android_cts" />\n</manifest>'
if "android_cts" not in s:
    s = s.replace("</manifest>", add)
    open(p, "w", encoding="utf-8").write(s)
    print("manifest: 已移除 android_cts")
PY
  fi
fi
rm -rf "$ROOT/cts"
rm -rf "$ROOT/.repo/project-objects/android_cts.git"
echo "cts 已清理"

# 2. 零散临时目录（早期解包/校验产物，已被 sysonly/ 与 backup/ 取代）
rm -rf /root/pandora-dt /root/recverify /root/pandora-gh /root/rdx2
rm -rf /root/rd6 /root/rd6.cpio
rm -f /root/TRACE_FILE /root/build-rec.log
echo "临时目录已清理"

# 3. 包缓存与日志
apt-get clean 2>/dev/null || true
journalctl --vacuum-size=32M >/dev/null 2>&1 || true
echo "缓存与日志已清理"

echo "=== 清理后 ==="
df -h / | tail -1
echo "=== /root 剩余 ==="
du -sh /root/* 2>/dev/null | sort -rh | head -6
