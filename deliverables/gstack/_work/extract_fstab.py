#!/usr/bin/env python3
"""从两侧 vendor_boot ramdisk 的 cpio 中提取 first_stage_ramdisk/fstab.qcom。

用途：让结论 A（fstab 全 flags 双向比对）可复现，而不只是一句结论。
输入：los_vendor_ramdisk.cpio / stock_vendor_ramdisk.cpio（同目录）
输出：fstab-qcom-los.txt / fstab-qcom-stock.txt
用法：python extract_fstab.py
"""
import hashlib
import os

HERE = os.path.dirname(os.path.abspath(__file__))
PAIRS = [
    ("los_vendor_ramdisk.cpio", "fstab-qcom-los.txt"),
    ("stock_vendor_ramdisk.cpio", "fstab-qcom-stock.txt"),
]


def parse_cpio(path):
    """最小 newc(070701/070702) 解析器，只按名字找条目。"""
    data = open(path, "rb").read()
    i = 0
    while True:
        if data[i:i + 6] not in (b"070701", b"070702"):
            j = data.find(b"070701", i)
            if j < 0:
                return
            i = j
        hdr = data[i:i + 110]
        filesize = int(hdr[54:62], 16)
        namesize = int(hdr[94:102], 16)
        name = data[i + 110:i + 110 + namesize - 1].decode("utf8", "replace")
        body_off = i + (110 + namesize + 3) // 4 * 4
        body = data[body_off:body_off + filesize]
        yield name, body
        i = (body_off + filesize + 3) // 4 * 4
        if name == "TRAILER!!!":
            return


def main():
    for src, dst in PAIRS:
        found = False
        for name, body in parse_cpio(os.path.join(HERE, src)):
            if name.endswith("fstab.qcom"):
                out = os.path.join(HERE, dst)
                open(out, "wb").write(body)
                print(f"{src} -> {dst}  {name}  {len(body)} bytes  "
                      f"sha256={hashlib.sha256(body).hexdigest()}")
                found = True
        if not found:
            print(f"{src}: fstab.qcom NOT FOUND")


if __name__ == "__main__":
    main()
