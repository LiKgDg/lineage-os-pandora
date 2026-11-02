"""Minimal read-only EROFS reader (uncompressed: FLAT_PLAIN / FLAT_INLINE / CHUNK unsupported)."""
import struct

EROFS_SUPER_MAGIC = 0xE0F5E1E2
DATALAYOUT_FLAT_PLAIN = 0
DATALAYOUT_FLAT_COMPRESSION_LEGACY = 1
DATALAYOUT_FLAT_INLINE = 2
DATALAYOUT_FLAT_COMPRESSION = 3
DATALAYOUT_CHUNK_BASED = 4


class Erofs:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(1024)
        sb = self.f.read(128)
        magic = struct.unpack_from("<I", sb, 0)[0]
        if magic != EROFS_SUPER_MAGIC:
            raise ValueError("not erofs: %08x" % magic)
        self.blkszbits = sb[12]
        self.bs = 1 << self.blkszbits
        self.root_nid = struct.unpack_from("<H", sb, 14)[0]
        self.blocks = struct.unpack_from("<I", sb, 36)[0]
        self.meta_blkaddr = struct.unpack_from("<I", sb, 40)[0]
        self.feat_incompat = struct.unpack_from("<I", sb, 80)[0]

    def _read_meta(self, nid, size):
        off = self.meta_blkaddr * self.bs + nid * 32
        self.f.seek(off)
        return self.f.read(size), off

    def inode(self, nid):
        hdr, off = self._read_meta(nid, 32)
        i_format = struct.unpack_from("<H", hdr, 0)[0]
        xattr_icount = struct.unpack_from("<H", hdr, 2)[0]
        extended = i_format & 1
        datalayout = (i_format >> 1) & 7
        if extended:
            hdr, off = self._read_meta(nid, 64)
            i_mode = struct.unpack_from("<H", hdr, 4)[0]
            i_size = struct.unpack_from("<Q", hdr, 8)[0]
            raw = struct.unpack_from("<I", hdr, 16)[0]
            inode_isize = 64
        else:
            i_mode = struct.unpack_from("<H", hdr, 4)[0]
            i_size = struct.unpack_from("<I", hdr, 8)[0]
            raw = struct.unpack_from("<I", hdr, 16)[0]
            inode_isize = 32
        if xattr_icount:
            xattr_isize = 12 + 4 * (xattr_icount - 1)
        else:
            xattr_isize = 0
        return dict(nid=nid, mode=i_mode, size=i_size, raw_blkaddr=raw,
                    datalayout=datalayout, inode_off=off,
                    data_off_in_meta=off + inode_isize + xattr_isize,
                    inode_isize=inode_isize, xattr_isize=xattr_isize)

    def read_file(self, ino):
        size = ino["size"]
        dl = ino["datalayout"]
        if dl == DATALAYOUT_FLAT_PLAIN:
            self.f.seek(ino["raw_blkaddr"] * self.bs)
            return self.f.read(size)
        if dl == DATALAYOUT_FLAT_INLINE:
            # EROFS FLAT_INLINE: leading blocks live at raw_blkaddr, the TAIL block is inline.
            nblocks = (size + self.bs - 1) // self.bs
            inline_len = size - (nblocks - 1) * self.bs if nblocks else 0
            raw_len = size - inline_len
            data = b""
            if raw_len > 0:
                self.f.seek(ino["raw_blkaddr"] * self.bs)
                data = self.f.read(raw_len)
            self.f.seek(ino["data_off_in_meta"])
            return data + self.f.read(inline_len)
        raise NotImplementedError("datalayout %d (compressed/chunked)" % dl)

    def readdir(self, ino):
        """EROFS dirent names are NOT NUL-terminated: length = next_nameoff - nameoff."""
        data = self.read_file(ino)
        out = {}
        bs = self.bs
        pos = 0
        while pos < len(data):
            blk_start = pos - (pos % bs)
            if pos + 12 > len(data):
                break
            _, first_nameoff, _, _ = struct.unpack_from("<QHBB", data, pos)
            if first_nameoff == 0:
                break
            arr_end = blk_start + first_nameoff
            blk_end = min(blk_start + bs, len(data))
            entries = []
            p = pos
            while p + 12 <= min(arr_end, len(data)):
                nid, nameoff, ftype, _ = struct.unpack_from("<QHBB", data, p)
                entries.append((nid, nameoff, ftype))
                p += 12
            for k, (nid, nameoff, ftype) in enumerate(entries):
                start = blk_start + nameoff
                end = blk_start + entries[k + 1][1] if k + 1 < len(entries) else blk_end
                if end <= start:
                    continue
                name = data[start:end].decode("utf-8", "replace")
                if name:
                    out[name] = (nid, ftype)
            pos = blk_start + bs
        return out

    def lookup(self, path):
        ino = self.inode(self.root_nid)
        for part in [p for p in path.split("/") if p]:
            entries = self.readdir(ino)
            if part not in entries:
                return None
            ino = self.inode(entries[part][0])
        return ino

    def cat(self, path):
        ino = self.lookup(path)
        return None if ino is None else self.read_file(ino)
