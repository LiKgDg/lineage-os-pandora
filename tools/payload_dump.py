#!/usr/bin/env python3
"""Minimal Android OTA payload.bin dumper (A/B full & incremental).

Usage:
    payload_dump.py <ota.zip> <outdir> [partition ...]
    payload_dump.py --list <ota.zip>

Only implements what a full-OTA dump needs: REPLACE / REPLACE_BZ / REPLACE_XZ /
ZERO / DISCARD. Incremental-only ops (SOURCE_COPY, *BSDIFF, PUFFDIFF, ZUCCHINI)
are reported and skipped.
"""

import bz2
import lzma
import os
import struct
import sys
import zipfile

BLOCK = 4096


def read_varint(buf, i):
    result = 0
    shift = 0
    while True:
        b = buf[i]
        i += 1
        result |= (b & 0x7F) << shift
        if not (b & 0x80):
            return result, i
        shift += 7


def parse_msg(buf):
    """Generic protobuf field walker -> list of (field_no, wire_type, value)."""
    out = []
    i = 0
    n = len(buf)
    while i < n:
        key, i = read_varint(buf, i)
        field, wt = key >> 3, key & 7
        if wt == 0:
            val, i = read_varint(buf, i)
        elif wt == 1:
            val = buf[i:i + 8]
            i += 8
        elif wt == 2:
            ln, i = read_varint(buf, i)
            val = buf[i:i + ln]
            i += ln
        elif wt == 5:
            val = buf[i:i + 4]
            i += 4
        else:
            raise ValueError("unsupported wire type %d" % wt)
        out.append((field, wt, val))
    return out


def parse_extents(buf):
    """Repeated Extent { start_block = 1; num_blocks = 2; }"""
    exts = []
    start = num = 0
    for field, _wt, val in parse_msg(buf):
        if field == 1:
            start = val
        elif field == 2:
            num = val
    exts.append((start, num))
    return exts


def parse_op(buf):
    op = {"type": 0, "data_offset": 0, "data_length": 0, "dst": []}
    for field, wt, val in parse_msg(buf):
        if field == 1:
            op["type"] = val
        elif field == 2:
            op["data_offset"] = val
        elif field == 3:
            op["data_length"] = val
        elif field == 6 and wt == 2:
            op["dst"].append(parse_extents(val)[0])
    return op


def parse_partition(buf):
    part = {"name": None, "ops": []}
    for field, wt, val in parse_msg(buf):
        if field == 1 and wt == 2:
            part["name"] = val.decode("utf-8", "replace")
        elif field == 8 and wt == 2:
            part["ops"].append(parse_op(val))
    return part


def parse_manifest(buf):
    parts = []
    for field, wt, val in parse_msg(buf):
        if field == 13 and wt == 2:
            parts.append(parse_partition(val))
    return parts


def load_manifest(zf):
    f = zf.open("payload.bin")
    magic = f.read(4)
    if magic != b"CrAU":
        raise SystemExit("not an update payload: %r" % magic)
    version = struct.unpack(">Q", f.read(8))[0]
    manifest_size = struct.unpack(">Q", f.read(8))[0]
    if version >= 2:
        sigsize = struct.unpack(">I", f.read(4))[0]
    else:
        sigsize = 0
    manifest = f.read(manifest_size)
    f.close()
    # InstallOperation.data_offset is relative to the start of the payload DATA
    # section, i.e. right after header + manifest + metadata signature.
    data_base = 24 + manifest_size + (sigsize if version >= 2 else 0)
    return version, parse_manifest(manifest), data_base


def dump_partition(zf, outdir, part, data_base=0):
    name = part["name"]
    path = os.path.join(outdir, name + ".img")
    # image size = highest dst block end
    end = 0
    for op in part["ops"]:
        for start, num in op["dst"]:
            end = max(end, (start + num) * BLOCK)
    with open(path, "wb") as out:
        out.truncate(end)
        src = zf.open("payload.bin")
        written = 0
        for op in part["ops"]:
            t = op["type"]
            if t in (0, 1, 8):
                src.seek(data_base + op["data_offset"])
                raw = src.read(op["data_length"])
                if t == 1:
                    data = bz2.decompress(raw)
                elif t == 8:
                    data = lzma.decompress(raw)
                else:
                    data = raw
            elif t in (6, 7):
                data = b""
            else:
                print("  ! %s: skip unsupported op type %d" % (name, t))
                continue
            pos = 0
            for start, num in op["dst"]:
                span = num * BLOCK
                out.seek(start * BLOCK)
                if t in (6, 7):
                    out.write(b"\0" * span)
                else:
                    chunk = data[pos:pos + span]
                    if len(chunk) < span:
                        chunk = chunk + b"\0" * (span - len(chunk))
                    out.write(chunk)
                    pos += span
                written += span
        src.close()
    print("  %-16s %12d bytes  %3d ops  -> %s" % (name, end, len(part["ops"]), path))
    return end


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    listing = args[0] == "--list"
    if listing:
        args = args[1:]
    zip_path, outdir = args[0], args[1] if len(args) > 1 else None
    wanted = args[2:]

    zf = zipfile.ZipFile(zip_path)
    version, parts, data_base = load_manifest(zf)
    print("payload major version %d, %d partitions" % (version, len(parts)))
    if listing:
        for p in parts:
            total = 0
            for op in p["ops"]:
                for start, num in op["dst"]:
                    total = max(total, (start + num) * BLOCK)
            print("  %-20s %12d bytes  %3d ops" % (p["name"], total, len(p["ops"])))
        return

    os.makedirs(outdir, exist_ok=True)
    for p in parts:
        if wanted and p["name"] not in wanted:
            continue
        dump_partition(zf, outdir, p, data_base)


if __name__ == "__main__":
    main()
