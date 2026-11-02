#!/usr/bin/env python3
"""vendor_boot.img -> 解压后的 vendor ramdisk cpio（newc）。

用法: python3 wsl-vb2cpio.py <vendor_boot.img> <out.cpio>
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from bootimg import parse_vendor_boot      # noqa: E402
from lz4legacy import decompress_any       # noqa: E402


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    img, out = sys.argv[1], sys.argv[2]
    info = parse_vendor_boot(img)
    with open(img, "rb") as f:
        f.seek(info["vendor_ramdisk_off"])
        raw = f.read(info["vendor_ramdisk_size"])
    data, how = decompress_any(raw)
    with open(out, "wb") as f:
        f.write(data)
    print(f"  {os.path.basename(img)}: vendor_ramdisk {len(raw)} -> cpio {len(data)} ({how})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
