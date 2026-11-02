"""Reassemble a partition image from a CrAU payload by applying its operations."""
import sys, os, lzma, bz2, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from payload import Payload, get_one, get_fields

OP_REPLACE = 0
OP_REPLACE_BZ = 1
OP_MOVE = 2
OP_BSDIFF = 3
OP_SOURCE_COPY = 4
OP_SOURCE_BSDIFF = 5
OP_ZERO = 6
OP_DISCARD = 7
OP_REPLACE_XZ = 8


def block_size(p):
    bs = get_one(p.manifest, 3, 0)
    return bs or 4096


def reassemble(p, name, out_path, verbose=True):
    parts = {pt["name"]: pt for pt in p.partitions()}
    if name not in parts:
        raise KeyError(name)
    pt = parts[name]
    bs = block_size(p)
    size = pt["new_size"]
    nblocks = (size + bs - 1) // bs
    if verbose:
        print(f"[{name}] new_size={size} block_size={bs} blocks={nblocks} ops={len(pt['ops'])}", flush=True)

    out = open(out_path, "wb")
    out.truncate(size)
    done = 0
    for idx, op in enumerate(pt["ops"]):
        t = op["type"]
        if t in (OP_ZERO, OP_DISCARD):
            payload = None
        elif t == OP_REPLACE:
            payload = p.read_op_data(op)
        elif t == OP_REPLACE_XZ:
            raw = p.read_op_data(op)
            payload = lzma.decompress(raw, format=lzma.FORMAT_XZ)
        elif t == OP_REPLACE_BZ:
            raw = p.read_op_data(op)
            payload = bz2.decompress(raw)
        else:
            raise NotImplementedError(f"op type {t} at index {idx} (need old data / bsdiff)")
        pos = 0
        for sb, nb in op["dst"]:
            chunk_len = nb * bs
            if payload is not None:
                chunk = payload[pos:pos + chunk_len]
                if len(chunk) < chunk_len:
                    raise ValueError(f"op {idx}: short payload {len(chunk)}<{chunk_len}")
                out.seek(sb * bs)
                out.write(chunk)
                pos += chunk_len
        done += 1
        if verbose and (done % 50 == 0 or done == len(pt["ops"])):
            print(f"  {done}/{len(pt['ops'])} ops", flush=True)
    out.close()
    return size


if __name__ == "__main__":
    zip_path = sys.argv[1]
    base = int(sys.argv[2])
    name = sys.argv[3]
    outp = sys.argv[4]
    p = Payload(zip_path, base=base)
    n = reassemble(p, name, outp)
    print("wrote", outp, n, "bytes")
