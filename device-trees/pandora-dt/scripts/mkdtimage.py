#!/usr/bin/env python3
# Minimal, dependency-free Android dt_table (dtbo.img/dt.img) packer.
# Layout follows AOSP system/libufdt dt_table_header / dt_table_entry (version 0).
#
# Usage:
#   mkdtimage.py create OUT.img [--page_size 4096] [--packed]
#                              [--meta id,rev,c0,c1,c2,c3]...
#                              DTB1 [DTB2 ...]
#   mkdtimage.py dump IMG
#
# --packed  各 entry 紧贴 entry 表连续存放（原厂 dtbo.img 的实际布局：
#           首个 entry 位于 0x60 = 32 字节头 + 2×32 字节 entry 表）；
#           默认按 page_size 对齐，供需要页对齐的场景使用。
# --meta    entry 的 id/rev/custom[4]，按出现顺序与 DTB 一一对应，
#           缺省补 0；用于与原厂 dtbo.img 的 entry 元数据逐项对齐。
import struct, sys

DT_TABLE_MAGIC = 0xD7B7AB1E
FDT_MAGIC = 0xD00DFEED
HEADER_SIZE = 32
ENTRY_SIZE = 32


def align_up(v, a):
    return (v + a - 1) // a * a


def parse_meta(text):
    parts = [int(x, 0) for x in text.split(",")]
    if len(parts) != 6:
        raise SystemExit("--meta 需要 6 个整数: id,rev,custom0,custom1,custom2,custom3")
    return parts


def create(out_path, dtbs, page_size=4096, packed=False, metas=()):
    blobs = []
    for p in dtbs:
        b = open(p, "rb").read()
        (magic, total) = struct.unpack_from(">2I", b, 0)
        if magic != FDT_MAGIC:
            raise SystemExit(f"{p}: not a flat device-tree blob (magic 0x{magic:08x})")
        if total != len(b):
            print(f"[mkdtimage] 警告: {p} 头部 totalsize={total} 与文件长度 {len(b)} 不符")
        blobs.append(b)

    n = len(blobs)
    entry_base = HEADER_SIZE + n * ENTRY_SIZE
    cursor = entry_base if packed else align_up(entry_base, page_size)
    entries = []
    regions = []
    for i, b in enumerate(blobs):
        if not packed and i:
            cursor = align_up(cursor, page_size)
        entries.append((i, len(b), cursor))
        regions.append((cursor, b))
        cursor += len(b)
    total = cursor if packed else align_up(cursor, page_size)

    img = bytearray(total)
    struct.pack_into(">8I", img, 0,
                     DT_TABLE_MAGIC, total, HEADER_SIZE, ENTRY_SIZE,
                     n, HEADER_SIZE, page_size, 0)
    for i, size, off in entries:
        meta = metas[i] if i < len(metas) else [0] * 6
        struct.pack_into(">8I", img, HEADER_SIZE + i * ENTRY_SIZE,
                         size, off, meta[0], meta[1],
                         meta[2], meta[3], meta[4], meta[5])
    for off, b in regions:
        img[off:off + len(b)] = b
    open(out_path, "wb").write(img)
    print(f"[mkdtimage] {out_path}: {n} dtb(s), total={total}, page={page_size}, "
          f"layout={'packed' if packed else 'aligned'}")


def dump(img_path):
    d = open(img_path, "rb").read()
    magic, total, hsz, esz, cnt, eoff, page, ver = struct.unpack_from(">8I", d, 0)
    if magic != DT_TABLE_MAGIC:
        raise SystemExit(f"not a dt_table (magic 0x{magic:08x})")
    print(f"magic=0x{magic:08x} total={total} entries={cnt} page={page} ver={ver} "
          f"file={len(d)}")
    for i in range(cnt):
        size, off, eid, rev, c0, c1, c2, c3 = struct.unpack_from(">8I", d, eoff + i * esz)
        print(f"  [{i}] offset={off} size={size} id=0x{eid:x} rev={rev} "
              f"custom={c0},{c1},{c2},{c3}")


def main(argv):
    if len(argv) >= 2 and argv[0] == "create":
        page = 4096
        packed = False
        metas = []
        out = None
        dtbs = []
        rest = argv[1:]
        i = 0
        while i < len(rest):
            a = rest[i]
            if a == "--page_size":
                page = int(rest[i + 1]); i += 2
            elif a == "--packed":
                packed = True; i += 1
            elif a == "--meta":
                metas.append(parse_meta(rest[i + 1])); i += 2
            elif a.startswith("--"):
                raise SystemExit(f"未知选项 {a}")
            else:
                if out is None:
                    out = a
                else:
                    dtbs.append(a)
                i += 1
        if out is None or not dtbs:
            raise SystemExit("用法: mkdtimage.py create OUT.img [选项] DTB1 [DTB2 ...]")
        create(out, dtbs, page, packed, metas)
    elif len(argv) >= 2 and argv[0] == "dump":
        dump(argv[1])
    else:
        print(__doc__); sys.exit(1)


if __name__ == "__main__":
    main(sys.argv[1:])
