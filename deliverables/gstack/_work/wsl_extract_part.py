#!/usr/bin/env python3
"""从 A/B OTA payload.bin 提取指定分区（payload.bin 在 zip 内为 STORED，可按裸偏移直读）。

用法:
    python3 wsl_extract_part.py --out /root/work/gstack vendor_dlkm system_dlkm
    python3 wsl_extract_part.py vendor            # 默认输出到当前目录

输出文件名: <out>/stock_<partition>.img
"""
import argparse
import bz2
import lzma
import os
import struct
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from payload import Payload  # noqa: E402

DEFAULT_ZIP = ("/mnt/c/Users/MSI/Desktop/HB/1/2/2/lineage os/"
               "pandora-ota_full-OS4.0.5.0.XBLCNXM-user-17.0-a4da788249.zip")


def payload_base(zip_path):
    """payload.bin 在 zip 内的裸数据偏移（仅 STORED 可寻址）。"""
    zf = zipfile.ZipFile(zip_path)
    info = zf.getinfo("payload.bin")
    if info.compress_type != zipfile.ZIP_STORED:
        raise SystemExit(f"payload.bin 是压缩存储（type={info.compress_type}），无法按偏移直读")
    with open(zip_path, "rb") as f:
        f.seek(info.header_offset)
        hdr = f.read(30)
        nlen = struct.unpack_from("<H", hdr, 26)[0]
        elen = struct.unpack_from("<H", hdr, 28)[0]
    return info.header_offset + 30 + nlen + elen


def extract(p, parts, part, outpath):
    d = parts[part]
    size = d["new_size"]
    print(f"-- {part}: {len(d['ops'])} ops, new_size={size}")
    with open(outpath, "wb") as out:
        out.truncate(size)
        for op in d["ops"]:
            blob = p.read_op_data(op)
            t = op["type"]
            if t == 0:                       # REPLACE
                data = blob
            elif t == 1:                     # REPLACE_BZ
                data = bz2.decompress(blob)
            elif t == 8:                     # REPLACE_XZ
                data = lzma.decompress(blob)
            elif t == 6:                     # ZERO
                data = b"\0" * sum(nb * 4096 for _, nb in op["dst"])
            else:
                raise SystemExit(f"不支持的操作类型 {t}（分区 {part}）")
            pos = 0
            for sb, nb in op["dst"]:
                ln = nb * 4096
                out.seek(sb * 4096)
                out.write(data[pos:pos + ln])
                pos += ln
    print(f"   -> {outpath} ({os.path.getsize(outpath)} bytes)")


def main():
    ap = argparse.ArgumentParser(description="从 stock OTA 提取分区")
    ap.add_argument("partitions", nargs="+", help="分区名，如 vendor_dlkm")
    ap.add_argument("--out", default=".", help="输出目录（默认当前目录）")
    ap.add_argument("--zip", default=DEFAULT_ZIP, help="OTA zip 路径")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    base = payload_base(a.zip)
    print(f"payload.bin raw offset: {base}")
    p = Payload(a.zip, base)
    parts = {d["name"]: d for d in p.partitions()}
    print(f"partitions: {len(parts)}")
    for name in a.partitions:
        extract(p, parts, name, os.path.join(a.out, f"stock_{name}.img"))


if __name__ == "__main__":
    main()
