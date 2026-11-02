"""Hand-rolled protobuf wire-format reader + Android OTA payload.bin (CrAU) parser.
No schema needed: varint + length-delimited + fixed32/64 are sufficient."""
import struct


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


def iter_fields(buf):
    """Yield (field_number, wire_type, value). wire_type 0=varint,1=fixed64,2=LEN,5=fixed32."""
    i = 0
    n = len(buf)
    while i < n:
        key, i = read_varint(buf, i)
        fnum = key >> 3
        wt = key & 7
        if wt == 0:
            v, i = read_varint(buf, i)
        elif wt == 1:
            v = buf[i:i + 8]; i += 8
        elif wt == 2:
            ln, i = read_varint(buf, i)
            v = buf[i:i + ln]; i += ln
        elif wt == 5:
            v = buf[i:i + 4]; i += 4
        else:
            raise ValueError("unsupported wire type %d at %d" % (wt, i))
        yield fnum, wt, v


def get_fields(buf, want):
    return [v for f, w, v in iter_fields(buf) if f == want]


def get_one(buf, want, default=None):
    for f, w, v in iter_fields(buf):
        if f == want:
            return v
    return default


class OffsetFile:
    """File-like view of a byte range inside another file (used for payload.bin in a STORED zip)."""

    def __init__(self, path, base):
        self.f = open(path, "rb")
        self.base = base
        self.f.seek(base)

    def seek(self, off, whence=0):
        assert whence == 0
        return self.f.seek(self.base + off)

    def read(self, n=-1):
        return self.f.read(n)


class Payload:
    def __init__(self, path, base=0):
        self.path = path
        self.f = OffsetFile(path, base) if base else open(path, "rb")
        head = self.f.read(24)
        assert head[:4] == b"CrAU", head[:4]
        self.version = struct.unpack_from(">Q", head, 4)[0]
        self.manifest_size = struct.unpack_from(">Q", head, 12)[0]
        self.sig_size = struct.unpack_from(">I", head, 20)[0]
        self.manifest_off = 24
        self.data_off = 24 + self.manifest_size + self.sig_size
        self.f.seek(self.manifest_off)
        self.manifest = self.f.read(self.manifest_size)

    def partitions(self):
        """Return list of dicts: name, ops[], new_size."""
        out = []
        for pu in get_fields(self.manifest, 13):
            name = get_one(pu, 1)
            if isinstance(name, int):
                name = str(name)
            name = name.decode() if isinstance(name, bytes) else str(name)
            ops = []
            for op in get_fields(pu, 8):
                otype = get_one(op, 1, 0)
                data_offset = get_one(op, 2, 0)
                data_length = get_one(op, 3, 0)
                dst = []
                for ext in get_fields(op, 6):
                    sb = get_one(ext, 1, 0)
                    nb = get_one(ext, 2, 0)
                    dst.append((sb, nb))
                ops.append(dict(type=otype, data_offset=data_offset,
                                data_length=data_length, dst=dst))
            npi = get_one(pu, 7, None)
            new_size = get_one(npi, 1, 0) if npi else 0
            out.append(dict(name=name, ops=ops, new_size=new_size))
        return out

    def read_op_data(self, op):
        self.f.seek(self.data_off + op["data_offset"])
        return self.f.read(op["data_length"])
