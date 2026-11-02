"""Minimal cpio newc (070701/070702) parser."""
import struct


def parse_cpio(data):
    """Yield dicts: name, mode, size, data, offset."""
    off = 0
    n = len(data)
    while off + 110 <= n:
        magic = data[off:off + 6]
        if magic not in (b"070701", b"070702"):
            break
        f = data[off + 6: off + 110]
        namesize = int(f[88:96], 16)
        filesize = int(f[48:56], 16)
        mode = int(f[8:16], 16)
        name = data[off + 110: off + 110 + namesize - 1].decode("utf-8", "replace")
        hdr_end = off + 110 + namesize
        hdr_end = (hdr_end + 3) & ~3
        fdata = data[hdr_end: hdr_end + filesize]
        yield dict(name=name, mode=mode, size=filesize, data=fdata, offset=off)
        if name == "TRAILER!!!":
            break
        nxt = hdr_end + filesize
        off = (nxt + 3) & ~3


def list_names(data, prefix=""):
    return [e["name"] for e in parse_cpio(data) if e["name"].startswith(prefix)]


def extract(data, want):
    for e in parse_cpio(data):
        if e["name"].lstrip("./") == want.lstrip("./") or e["name"] == want:
            return e["data"]
    return None
