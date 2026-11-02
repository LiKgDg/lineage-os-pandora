"""Minimal read-only ext4 reader: path lookup + file read. Supports extents (depth<=2)."""
import struct

EXT4_EXTENTS_FL = 0x80000
S_IFMT = 0o170000
S_IFDIR = 0o040000


class Ext4:
    def __init__(self, path):
        self.f = open(path, "rb")
        self.f.seek(1024)
        sb = self.f.read(1024)
        if struct.unpack_from("<H", sb, 56)[0] != 0xEF53:
            raise ValueError("not ext4")
        self.inodes_count = struct.unpack_from("<I", sb, 0)[0]
        self.first_data_block = struct.unpack_from("<I", sb, 20)[0]
        self.log_bs = struct.unpack_from("<I", sb, 24)[0]
        self.bs = 1024 << self.log_bs
        self.blocks_per_group = struct.unpack_from("<I", sb, 32)[0]
        self.inodes_per_group = struct.unpack_from("<I", sb, 40)[0]
        self.inode_size = struct.unpack_from("<H", sb, 88)[0]
        self.rev = struct.unpack_from("<I", sb, 76)[0]
        self.incompat = struct.unpack_from("<I", sb, 96)[0]
        self.desc_size = struct.unpack_from("<H", sb, 254)[0] if self.rev >= 1 else 32
        if self.desc_size == 0:
            self.desc_size = 32
        self.is64 = bool(self.incompat & 0x80)  # EXT4_FEATURE_INCOMPAT_64BIT
        self.gd_off = (self.first_data_block + 1) * self.bs
        self._gd_cache = {}

    def _gd(self, g):
        if g in self._gd_cache:
            return self._gd_cache[g]
        self.f.seek(self.gd_off + g * self.desc_size)
        d = self.f.read(self.desc_size)
        inode_table = struct.unpack_from("<I", d, 8)[0]
        if self.is64:
            inode_table |= struct.unpack_from("<I", d, 0x28)[0] << 32
        self._gd_cache[g] = inode_table
        return inode_table

    def read_inode(self, ino):
        g, idx = divmod(ino - 1, self.inodes_per_group)
        off = self._gd(g) * self.bs + idx * self.inode_size
        self.f.seek(off)
        return self.f.read(self.inode_size)

    def _inode_blocks(self, inode):
        """Return list of (logical_block_start, physical_block_start, count)."""
        mode = struct.unpack_from("<H", inode, 0)[0]
        size_lo = struct.unpack_from("<I", inode, 4)[0]
        size_hi = struct.unpack_from("<I", inode, 108)[0]
        size = size_lo | (size_hi << 32)
        flags = struct.unpack_from("<I", inode, 32)[0]
        blocks = []
        if flags & EXT4_EXTENTS_FL:
            self._extent_node(inode[40:100], blocks, 0)
        else:
            iblock = struct.unpack_from("<15I", inode, 40)
            for i in range(12):
                if iblock[i]:
                    blocks.append((i, iblock[i], 1))
        return size, blocks

    def _extent_node(self, node, out, base_logical):
        magic, entries, mx, depth = struct.unpack_from("<HHHH", node, 0)
        if magic != 0xF30A:
            raise ValueError("bad extent magic %04x" % magic)
        if depth == 0:
            for i in range(entries):
                o = 12 + i * 12
                ee_block, ee_len, hi, lo = struct.unpack_from("<IHHI", node, o)
                start = lo | (hi << 32)
                ln = ee_len & 0x7FFF
                if ee_len > 32768:  # uninitialized
                    ln = ee_len - 32768
                out.append((ee_block, start, ln))
        else:
            for i in range(entries):
                o = 12 + i * 12
                ei_block, leaf_lo, leaf_hi = struct.unpack_from("<IIH", node, o)
                leaf = leaf_lo | (leaf_hi << 32)
                self.f.seek(leaf * self.bs)
                self._extent_node(self.f.read(self.bs), out, ei_block)

    def read_file(self, inode):
        size, blocks = self._inode_blocks(inode)
        data = bytearray()
        for lb, pb, cnt in sorted(blocks):
            if len(data) >= size:
                break
            if lb * self.bs > len(data):
                data.extend(b"\0" * (lb * self.bs - len(data)))
            self.f.seek(pb * self.bs)
            data.extend(self.f.read(cnt * self.bs))
        return bytes(data[:size])

    def _readdir(self, inode):
        data = self.read_file(inode)
        out = {}
        off = 0
        while off + 8 <= len(data):
            ino, rec_len, name_len, ftype = struct.unpack_from("<IHBB", data, off)
            if rec_len < 8:
                break
            if ino and name_len:
                out[data[off + 8:off + 8 + name_len].decode("utf-8", "replace")] = (ino, ftype)
            off += rec_len
        return out

    def lookup(self, path):
        ino = 2
        parts = [p for p in path.split("/") if p]
        for p in parts:
            entries = self._readdir(self.read_inode(ino))
            if p not in entries:
                return None
            ino = entries[p][0]
        return self.read_inode(ino)

    def cat(self, path):
        inode = self.lookup(path)
        if inode is None:
            return None
        return self.read_file(inode)

    def listdir(self, path):
        inode = self.lookup(path)
        if inode is None:
            return None
        return self._readdir(inode)
