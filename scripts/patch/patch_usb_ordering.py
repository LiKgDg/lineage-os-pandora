#!/usr/bin/env python3
"""Add deterministic USB mode-switch ordering to init.recovery.qcom.rc.

Problem: sys.usb.ffs.ready is a single global flag shared by adb and fastboot.
While adbd is alive it stays 1, so `setprop sys.usb.config fastboot` fires the
fastboot block in init.recovery.usb.rc immediately -- before fastbootd starts and
before adbd stops. Binding UDC at that moment attaches an ffs.fastboot function
that has no descriptors yet, the host enumerates a dead device, fastbootd then
fails to open /dev/usb-ffs/fastboot, and the gadget is left unbound: the PC sees
no USB device at all.

Fix: stop the old daemon and clear ffs.ready *before* starting the new one, so
ffs.ready=1 can only be set by the daemon we actually want.
"""

P = "/root/android/lineage/device/xiaomi/pandora/recovery/root/init.recovery.qcom.rc"
MARKER = "# ── rc-mode: USB 模式切换的确定性时序"

BLOCK = """
# ── rc-mode: USB 模式切换的确定性时序 ────────────────────────────
# sys.usb.ffs.ready 是 adb / fastboot 共用的全局标志，adbd 存活时它就是 1。
# 若在 adbd 还活着时切到 fastboot，init.recovery.usb.rc 的 fastboot 分支会立刻
# 触发，在 fastbootd 尚未启动、ffs.fastboot 还没有描述符时就去绑定 UDC ——
# 主机枚举到一个空设备，fastbootd 随后又起不来，最终 gadget 处于解绑状态，
# 表现为"电脑上 USB 设备整个消失"。
# 因此切换前必须先停掉旧服务并清零 ffs.ready，再启动新服务。
on property:sys.usb.config=fastboot
    stop adbd
    setprop sys.usb.ffs.ready 0
    start fastbootd

on property:sys.usb.config=adb
    stop fastbootd
    setprop sys.usb.ffs.ready 0
    start adbd
"""

src = open(P, encoding="utf-8").read()
if MARKER in src:
    print("already patched")
else:
    open(P, "w", encoding="utf-8").write(src.rstrip("\n") + "\n" + BLOCK)
    print("appended ordering block")
