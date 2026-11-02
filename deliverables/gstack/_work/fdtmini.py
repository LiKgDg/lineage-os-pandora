"""Minimal FDT (flattened device tree) reader: find nodes by name/compatible and dump properties."""
import struct

FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9


class Fdt:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        d = self.data
        magic, totalsize, off_struct, off_strings, off_rsvmap = struct.unpack_from(">IIIII", d, 0)
        if magic != 0xD00DFEED:
            raise ValueError("not FDT: %08x" % magic)
        self.totalsize = totalsize
        self.off_struct = off_struct
        self.off_strings = off_strings
        self.size_strings = struct.unpack_from(">I", d, 32)[0]

    def _str(self, off):
        start = self.off_strings + off
        end = self.data.find(b"\0", start)
        return self.data[start:end].decode("utf-8", "replace")

    def walk(self):
        """Yield (path, props_dict) for every node."""
        d = self.data
        i = self.off_struct
        path = []
        props = {}
        while i < len(d):
            tag = struct.unpack_from(">I", d, i)[0]
            i += 4
            if tag == FDT_BEGIN_NODE:
                end = d.find(b"\0", i)
                name = d[i:end].decode("utf-8", "replace")
                i = (end + 4) & ~3
                path.append(name)
                props = {}
            elif tag == FDT_END_NODE:
                if path:
                    yield "/" + "/".join(path), props
                    path.pop()
                props = {}
            elif tag == FDT_PROP:
                ln, nameoff = struct.unpack_from(">II", d, i)
                i += 8
                val = d[i:i + ln]
                i = (i + ln + 3) & ~3
                props[self._str(nameoff)] = val
            elif tag == FDT_NOP:
                pass
            elif tag == FDT_END:
                break
            else:
                break


def find_nodes(fdt, needle=b"ramoops"):
    out = []
    for path, props in fdt.walk():
        blob = b"".join(props.values())
        if needle in path.encode() or needle in blob:
            out.append((path, props))
    return out


def dump_node(path, props, indent="  "):
    lines = [path + " {"]
    for k, v in props.items():
        if v.endswith(b"\0") and all(32 <= c < 127 for c in v[:-1]):
            lines.append(f"{indent}{k} = {v[:-1].decode()!r};")
        else:
            lines.append(f"{indent}{k} = <{v.hex()}>;  # raw")
    lines.append("};")
    return "\n".join(lines)
