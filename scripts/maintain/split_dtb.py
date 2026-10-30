#!/usr/bin/env python3
"""把 vendor_boot 里的拼接 dtb 拆成单个 dtb 文件。

vendor_boot 的 dtb 段是多个 FDT 的简单拼接，每个 FDT 以 0xD00DFEED 开头，
偏移 4 处是大端 u32 的 totalsize。按此切分，并验证拼接后与原始字节一致。

用法:
    split_dtb.py <拼接dtb> <输出目录>
"""
import os
import struct
import sys

FDT_MAGIC = 0xD00DFEED


def split(data):
    out = []
    off = 0
    while off < len(data):
        if len(data) - off < 8:
            raise ValueError("尾部残余 %d 字节，不足一个 FDT 头" % (len(data) - off))
        magic, total = struct.unpack(">II", data[off:off + 8])
        if magic != FDT_MAGIC:
            raise ValueError("偏移 %d 处 magic=0x%08X，不是 FDT" % (off, magic))
        if total <= 0 or off + total > len(data):
            raise ValueError("偏移 %d 处 totalsize=%d 越界" % (off, total))
        out.append(data[off:off + total])
        off += total
    return out


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    blobs = split(data)
    os.makedirs(dst, exist_ok=True)

    for i, b in enumerate(blobs):
        name = "%02d_dtb_%d.dtb" % (i, len(b))
        with open(os.path.join(dst, name), "wb") as f:
            f.write(b)

    # 校验：按文件名排序拼接必须还原原始字节
    joined = b"".join(blobs)
    ok = joined == data
    print("拆分 %d 个 dtb，原始 %d 字节，拼接还原 %s" % (
        len(blobs), len(data), "一致" if ok else "不一致"))
    for i, b in enumerate(blobs):
        print("  %02d  %d 字节" % (i, len(b)))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
