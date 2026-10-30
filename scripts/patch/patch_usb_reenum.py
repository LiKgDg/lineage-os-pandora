#!/usr/bin/env python3
"""Patch init.recovery.usb.rc so every USB config switch re-enumerates.

Root cause: each `on property:sys.usb.ffs.ready=1 && property:sys.usb.config=X`
block ends with `write /config/usb_gadget/g1/UDC ${sys.usb.controller}`.
If the gadget is already bound to that UDC, the kernel treats it as a no-op and
the host keeps the previous descriptors. That is why fastbootd starts but the PC
still sees the old adb interface (18d1:d001) instead of 18d1:4ee0.

Fix: write "none" to UDC first (kernel unbinds), then the existing bind line
re-enumerates with the new descriptors.
"""

import re
import sys

P = "/root/android/lineage/device/xiaomi/pandora/recovery/root/init.recovery.usb.rc"

MARKER = "# rc-mode: 解绑 UDC 以强制主机重新枚举"
INSERT = (
    "    # rc-mode: 解绑 UDC 以强制主机重新枚举\n"
    '    write /config/usb_gadget/g1/UDC "none"\n'
)

src = open(P, encoding="utf-8").read()
if MARKER in src:
    print("already patched")
    sys.exit(0)

# insert right before each configuration-name write inside a ffs.ready block
pattern = re.compile(
    r'(on property:sys\.usb\.ffs\.ready=1[^\n]*\n)(    write /config/usb_gadget/g1/configs/b\.1/strings/0x409/configuration)'
)
new, n = pattern.subn(lambda m: m.group(1) + INSERT + m.group(2), src)

if n == 0:
    print("PATTERN NOT FOUND")
    sys.exit(1)

open(P, "w", encoding="utf-8").write(new)
print("patched %d blocks" % n)
