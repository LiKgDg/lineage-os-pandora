#!/usr/bin/env python3
"""Minimal Android OTA payload.bin dumper (A/B full & incremental).

Usage:
    payload_dump.py <ota.zip> <outdir> [partition ...] [--verify]
    payload_dump.py --list <ota.zip>

Only implements what a full-OTA dump needs: REPLACE / REPLACE_BZ / REPLACE_XZ /
ZERO / DISCARD. Incremental-only ops (SOURCE_COPY, *BSDIFF, PUFFDIFF, ZUCCHINI)
cannot be reconstructed from a single package; they are detected up front and the
dump is refused unless --allow-incomplete is given.

--verify recomputes the sha256 of every dumped image and compares it with the
hash carried in the payload manifest (PartitionUpdate.new_partition_info).
"""

import bz2
import hashlib
import lzma
import os
import struct
import sys
import zipfile

BLOCK = 4096

# InstallOperation.Type values that carry the full data for their destination.
DATA_OPS = {0: "REPLACE", 1: "REPLACE_BZ", 8: "REPLACE_XZ"}
ZERO_OPS = {6: "ZERO", 7: "DISCARD"}
# Everything else needs the source image, i.e. this is an incremental package.
INCREMENTAL_OPS = {
    2: "MOVE", 3: "BSDIFF", 4: "SOURCE_COPY", 5: "SOURCE_BSDIFF",
    9: "PUFFDIFF", 10: "BROTLI_BSDIFF", 11: "ZUCCHINI",
    12: "LZ4DIFF_BSDIFF", 13: "LZ4DIFF_PUFFDIFF",
}


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


def parse_new_partition_info(buf):
    """PartitionInfo { size = 1; hash = 2; }"""
    info = {"size": 0, "hash": b""}
    for field, _wt, val in parse_msg(buf):
        if field == 1:
            info["size"] = val
        elif field == 2:
            info["hash"] = val
    return info


def parse_partition(buf):
    part = {"name": None, "ops": [], "new_info": None}
    for field, wt, val in parse_msg(buf):
        if field == 1 and wt == 2:
            part["name"] = val.decode("utf-8", "replace")
        elif field == 7 and wt == 2:
            part["new_info"] = parse_new_partition_info(val)
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


def image_size(part):
    end = 0
    for op in part["ops"]:
        for start, num in op["dst"]:
            end = max(end, (start + num) * BLOCK)
    return end


def incremental_ops(part):
    """Return the set of unsupported (incremental-only) op type names."""
    return {INCREMENTAL_OPS[op["type"]]
            for op in part["ops"] if op["type"] in INCREMENTAL_OPS}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.digest()


def verify_image(path, part):
    """Compare dumped image against the manifest's new_partition_info."""
    info = part["new_info"]
    if not info or not info["hash"]:
        return None, "manifest has no new_partition_info hash"
    size = os.path.getsize(path)
    if info["size"] and size != info["size"]:
        return False, "size %d != expected %d" % (size, info["size"])
    got = sha256_file(path)
    if got != info["hash"]:
        return False, "sha256 %s != expected %s" % (
            got.hex()[:16] + "...", info["hash"].hex()[:16] + "...")
    return True, "sha256 ok"


def dump_partition(zf, outdir, part, data_base=0, verify=False):
    name = part["name"]
    path = os.path.join(outdir, name + ".img")
    end = image_size(part)
    skipped = incremental_ops(part)

    with open(path, "wb") as out:
        out.truncate(end)
        src = zf.open("payload.bin")
        written = 0
        for op in part["ops"]:
            t = op["type"]
            if t in DATA_OPS:
                src.seek(data_base + op["data_offset"])
                raw = src.read(op["data_length"])
                if t == 1:
                    data = bz2.decompress(raw)
                elif t == 8:
                    data = lzma.decompress(raw)
                else:
                    data = raw
            elif t in ZERO_OPS:
                data = b""
            else:
                continue
            pos = 0
            for start, num in op["dst"]:
                span = num * BLOCK
                out.seek(start * BLOCK)
                if t in ZERO_OPS:
                    out.write(b"\0" * span)
                else:
                    chunk = data[pos:pos + span]
                    if len(chunk) < span:
                        chunk = chunk + b"\0" * (span - len(chunk))
                    out.write(chunk)
                    pos += span
                written += span
        src.close()

    note = ""
    if skipped:
        note = "  !! incomplete: %s" % ",".join(sorted(skipped))

    print("  %-16s %12d bytes  %3d ops  -> %s%s"
          % (name, end, len(part["ops"]), path, note))

    if verify:
        ok, msg = verify_image(path, part)
        if ok is True:
            print("      verify: PASS  (%s)" % msg)
        elif ok is False:
            print("      verify: FAIL  (%s)" % msg)
            return end, False
        else:
            print("      verify: SKIP  (%s)" % msg)
    return end, True


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)

    listing = args[0] == "--list"
    if listing:
        args = args[1:]
    verify = "--verify" in args
    allow_incomplete = "--allow-incomplete" in args
    args = [a for a in args if not a.startswith("--")]

    zip_path = args[0]
    outdir = args[1] if len(args) > 1 else None
    wanted = args[2:]

    zf = zipfile.ZipFile(zip_path)
    version, parts, data_base = load_manifest(zf)
    print("payload major version %d, %d partitions" % (version, len(parts)))

    if listing:
        for p in parts:
            inc = incremental_ops(p)
            flag = "  [incremental: %s]" % ",".join(sorted(inc)) if inc else ""
            print("  %-20s %12d bytes  %3d ops%s"
                  % (p["name"], image_size(p), len(p["ops"]), flag))
        return

    selected = [p for p in parts if not wanted or p["name"] in wanted]

    # An incremental package cannot be reconstructed without the source image.
    bad = [(p["name"], sorted(incremental_ops(p))) for p in selected
           if incremental_ops(p)]
    if bad and not allow_incomplete:
        print("\nERROR: this is an INCREMENTAL package, not a full OTA.")
        for name, ops in bad:
            print("  %-16s needs: %s" % (name, ",".join(ops)))
        print("Reconstructing these needs the source build; use the full OTA "
              "package instead, or pass --allow-incomplete to dump partial data.")
        raise SystemExit(2)

    os.makedirs(outdir, exist_ok=True)
    failures = []
    for p in selected:
        _size, ok = dump_partition(zf, outdir, p, data_base, verify)
        if not ok:
            failures.append(p["name"])

    if verify:
        print("\nverify summary: %d ok, %d failed"
              % (len(selected) - len(failures), len(failures)))
        if failures:
            print("failed: %s" % ", ".join(failures))
            raise SystemExit(1)


if __name__ == "__main__":
    main()
