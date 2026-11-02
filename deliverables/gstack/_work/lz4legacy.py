"""Pure-Python LZ4 decoders: legacy frame (0x184C2102) and modern frame (0x184D2204)."""
import struct


def lz4_block_decompress(src, expected=None):
    """Decompress a single raw LZ4 block."""
    out = bytearray()
    i = 0
    n = len(src)
    while i < n:
        token = src[i]; i += 1
        lit_len = token >> 4
        if lit_len == 15:
            while True:
                b = src[i]; i += 1
                lit_len += b
                if b != 255:
                    break
        if lit_len:
            out += src[i:i + lit_len]
            i += lit_len
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        if offset == 0:
            raise ValueError("bad lz4 offset 0 at %d" % i)
        match_len = token & 0x0F
        if match_len == 15:
            while True:
                b = src[i]; i += 1
                match_len += b
                if b != 255:
                    break
        match_len += 4
        start = len(out) - offset
        if start < 0:
            raise ValueError("match before start")
        for k in range(match_len):
            out.append(out[start + k])
    if expected is not None and len(out) != expected:
        raise ValueError("size mismatch %d != %d" % (len(out), expected))
    return bytes(out)


def is_legacy(data):
    return data[:4] == bytes.fromhex("02214c18")


def is_frame(data):
    return data[:4] == bytes.fromhex("04224d18")


def decompress_legacy(data):
    assert is_legacy(data)
    off = 4
    out = bytearray()
    blocks = 0
    while off + 4 <= len(data):
        (bsize,) = struct.unpack_from("<I", data, off)
        off += 4
        if bsize == 0:
            break
        blk = data[off:off + bsize]
        off += bsize
        out += lz4_block_decompress(blk)
        blocks += 1
    return bytes(out), blocks


def decompress_frame(data):
    """Minimal LZ4 frame decoder (no checksum verification)."""
    assert is_frame(data)
    off = 4
    flg = data[off]; off += 1
    bd = data[off]; off += 1
    has_content_size = (flg >> 3) & 1
    has_dict_id = flg & 1
    block_checksum = (flg >> 4) & 1
    content_checksum = (flg >> 2) & 1
    if has_content_size:
        off += 8
    if has_dict_id:
        off += 4
    off += 1  # header checksum
    out = bytearray()
    while off + 4 <= len(data):
        (bsize,) = struct.unpack_from("<I", data, off)
        off += 4
        if bsize == 0:
            break
        uncompressed = bool(bsize & 0x80000000)
        bsize &= 0x7FFFFFFF
        blk = data[off:off + bsize]
        off += bsize
        out += blk if uncompressed else lz4_block_decompress(blk)
        if block_checksum:
            off += 4
    return bytes(out)


def decompress_any(data):
    if is_legacy(data):
        return decompress_legacy(data)[0], "lz4-legacy"
    if is_frame(data):
        return decompress_frame(data), "lz4-frame"
    if data[:2] == b"\x1f\x8b":
        import gzip
        return gzip.decompress(data), "gzip"
    if data[:6] == bytes.fromhex("fd377a585a00"):
        import lzma
        return lzma.decompress(data), "xz"
    return data, "none"
