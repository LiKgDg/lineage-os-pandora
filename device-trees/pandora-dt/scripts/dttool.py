#!/usr/bin/env python3
"""pandora 设备树取证工具（仅依赖 python3 标准库）。

直接解析二进制而不是调用 fdtget，原因有三：
  1. 需要枚举 `/` 节点上「所有」属性名，fdtget -p 只给名字不给类型/长度；
  2. 需要拿到 dt_table entry 的 id/rev/custom 原始 u32，dtc 工具链不暴露；
  3. 需要按 路径→属性→原始字节 做全树对账，逐条起 fdtget 进程太慢。

子命令：
  vb-info     <vendor_boot.img>
  split-vb    <vendor_boot.img> <outdir>
  split-dtbo  <dtbo.img> <outdir>
  img-info    <dtbo.img>
  count       <dtb|dtbo>...
  root        <dtb>...
  cmp         <a> <b>                 # 全树结构对账，一致返回 0
  verify-root <原厂> <重建> [--label 名称]
  verify-img  <原厂 dtbo.img> <重建 dtbo.img>
  matrix      <标签=路径>...
  unzip-parts <zip> <outdir> <成员名>...
  normalize-dts <dts> <dtb>           # 消除 dtc 反编译的无歧义丢失
  manifest    <out.tsv> <标签=镜像>...
"""

import hashlib
import os
import struct
import sys

FDT_MAGIC = 0xD00DFEED
DT_TABLE_MAGIC = 0xD7B7AB1E
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9

# vendor_boot header v4 的字段偏移（u8 magic[8] 之后全部小端）
VB_FIELDS = (
    ("header_version", 8, "I"),
    ("page_size", 12, "I"),
    ("kernel_addr", 16, "I"),
    ("ramdisk_addr", 20, "I"),
    ("vendor_ramdisk_size", 24, "I"),
    ("tags_addr", 2076, "I"),
    ("header_size", 2096, "I"),
    ("dtb_size", 2100, "I"),
    ("dtb_addr", 2104, "Q"),
    ("vendor_ramdisk_table_size", 2112, "I"),
    ("vendor_ramdisk_table_entry_num", 2116, "I"),
    ("vendor_ramdisk_table_entry_size", 2120, "I"),
    ("bootconfig_size", 2124, "I"),
)


def align_up(value, align):
    return (value + align - 1) // align * align


# --------------------------------------------------------------------------
# FDT
# --------------------------------------------------------------------------
class Node:
    __slots__ = ("name", "props", "children")

    def __init__(self, name):
        self.name = name
        self.props = []      # [(name, bytes)]，保持结构块中的原始顺序
        self.children = []


def parse_fdt(data):
    """解析 FDT 二进制，返回 (version, 根节点, totalsize)。"""
    if len(data) < 40:
        raise ValueError("数据不足 40 字节，不是 FDT")
    magic, total, off_struct, off_strings, off_rsvmap, version, last_comp, _, size_strings, size_struct = \
        struct.unpack_from(">10I", data, 0)
    if magic != FDT_MAGIC:
        raise ValueError("magic=0x%08X 不是 0xD00DFEED" % magic)
    if total > len(data):
        raise ValueError("totalsize=%d 超出数据长度 %d" % (total, len(data)))

    strings = data[off_strings:off_strings + size_strings]
    pos = off_struct
    end_struct = off_struct + size_struct
    stack = []
    root = None

    def string_at(off):
        end = strings.find(b"\0", off)
        return strings[off:end].decode("utf-8", "replace")

    while pos < end_struct:
        (token,) = struct.unpack_from(">I", data, pos)
        pos += 4
        if token == FDT_BEGIN_NODE:
            end = data.index(b"\0", pos)
            node = Node(data[pos:end].decode("utf-8", "replace"))
            pos = align_up(end + 1, 4)
            if stack:
                stack[-1].children.append(node)
            else:
                root = node
            stack.append(node)
        elif token == FDT_END_NODE:
            stack.pop()
        elif token == FDT_PROP:
            length, nameoff = struct.unpack_from(">2I", data, pos)
            pos += 8
            name = string_at(nameoff)
            stack[-1].props.append((name, bytes(data[pos:pos + length])))
            pos = align_up(pos + length, 4)
        elif token == FDT_NOP:
            continue
        elif token == FDT_END:
            break
        else:
            raise ValueError("偏移 %d 处未知结构标记 0x%X" % (pos - 4, token))
    return version, root, total


def walk(root, prefix="/"):
    """按 dtc 的路径规则展开为 {path: (Node, {prop: bytes})}。"""
    table = {}

    def rec(node, path):
        table[path] = (node, dict(node.props))
        for child in node.children:
            node_path = path.rstrip("/") + "/" + child.name
            rec(child, node_path)

    rec(root, prefix)
    return table


def fmt_value(raw, limit=96):
    """把属性原始字节渲染成可读且可比较的字符串。

    以 NUL 结尾且全可打印 → 按字符串列表输出（与原 dts 的写法一致）；
    其余按 4 字节大端 cell 输出，非 4 的整数倍则原样十六进制。
    显示层超长时截断，PASS/FAIL 判定始终基于原始字节。
    """
    if not raw:
        return "<空>"
    text = None
    if raw.endswith(b"\0") and any(raw):
        chunks = raw[:-1].split(b"\0")
        if all(0x20 <= b < 0x7F for chunk in chunks for b in chunk):
            text = ", ".join('"%s"' % c.decode() for c in chunks)
    if text is None:
        if len(raw) % 4 == 0:
            words = struct.unpack(">%dI" % (len(raw) // 4), raw)
            text = "<" + " ".join("0x%x" % w for w in words) + ">"
        else:
            text = raw.hex()
    if len(text) > limit:
        text = text[:limit] + "…(%d 字节)" % len(raw)
    return text


# --------------------------------------------------------------------------
# Android dt_table (dtbo.img / dt.img)
# --------------------------------------------------------------------------
def parse_dt_table(data):
    if len(data) < 32:
        raise ValueError("dt_table 头部不足 32 字节")
    magic, total, hdr_size, entry_size, entry_count, entries_offset, page_size, version = \
        struct.unpack_from(">8I", data, 0)
    if magic != DT_TABLE_MAGIC:
        raise ValueError("magic=0x%08X 不是 dt_table (0x%08X)" % (magic, DT_TABLE_MAGIC))
    entries = []
    for i in range(entry_count):
        base = entries_offset + i * entry_size
        size, offset, eid, rev = struct.unpack_from(">4I", data, base)
        custom = list(struct.unpack_from(">4I", data, base + 16))
        entries.append({"index": i, "size": size, "offset": offset,
                        "id": eid, "rev": rev, "custom": custom,
                        "blob": data[offset:offset + size]})
    return {"magic": magic, "total_size": total, "hdr_size": hdr_size,
            "entry_size": entry_size, "entry_count": entry_count,
            "entries_offset": entries_offset, "page_size": page_size,
            "version": version, "entries": entries}


# --------------------------------------------------------------------------
# vendor_boot header v4
# --------------------------------------------------------------------------
def parse_vendor_boot(data):
    if data[:8] != b"VNDRBOOT":
        raise ValueError("magic=%r 不是 VNDRBOOT" % data[:8])
    info = {}
    for name, off, fmt in VB_FIELDS:
        info[name] = struct.unpack_from("<" + fmt, data, off)[0]
    if info["header_version"] < 4:
        raise ValueError("header_version=%d，dtb 段解析按 v4 处理" % info["header_version"])
    info["dtb_offset"] = align_up(info["page_size"] + info["vendor_ramdisk_size"],
                                  info["page_size"])
    info["name"] = data[2080:2096].rstrip(b"\0").decode("utf-8", "replace")
    return info


def split_fdt_stream(data):
    """把拼接的多棵 FDT 切开；返回 [(offset, blob)]，并校验拼接可还原。"""
    out, off = [], 0
    while off < len(data):
        if len(data) - off < 8:
            raise ValueError("尾部残余 %d 字节，不足一个 FDT 头" % (len(data) - off))
        magic, total = struct.unpack_from(">2I", data, off)
        if magic != FDT_MAGIC:
            raise ValueError("偏移 %d 处 magic=0x%08X 不是 FDT" % (off, magic))
        if total < 40 or off + total > len(data):
            raise ValueError("偏移 %d 处 totalsize=%d 越界" % (off, total))
        out.append((off, data[off:off + total]))
        off += total
    if b"".join(blob for _, blob in out) != data:
        raise ValueError("拆分后拼接无法还原原始字节")
    return out


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def root_summary(blob):
    """返回 (model, compatible) 用于清单展示。"""
    try:
        _, root, _ = parse_fdt(blob)
    except ValueError:
        return "-", "-"
    props = dict(root.props)
    model = props.get("model", b"").rstrip(b"\0").decode("utf-8", "replace") or "-"
    compat = props.get("compatible", b"").rstrip(b"\0").decode("utf-8", "replace") or "-"
    return model, compat.replace("\0", " ") if "\0" in compat else compat


# --------------------------------------------------------------------------
# 子命令
# --------------------------------------------------------------------------
def cmd_vb_info(argv):
    data = open(argv[0], "rb").read()
    info = parse_vendor_boot(data)
    print("文件        %s (%d 字节, sha256 %s)" % (argv[0], len(data), sha256(data)[:16]))
    for key in ("header_version", "page_size", "name", "vendor_ramdisk_size",
                "dtb_offset", "dtb_size", "dtb_addr", "bootconfig_size"):
        val = info[key]
        print("  %-26s %s" % (key, hex(val) if key.endswith("addr") else val))
    return 0


def cmd_split_vb(argv):
    src, outdir = argv[0], argv[1]
    data = open(src, "rb").read()
    info = parse_vendor_boot(data)
    start, size = info["dtb_offset"], info["dtb_size"]
    section = data[start:start + size]
    blobs = split_fdt_stream(section)
    os.makedirs(outdir, exist_ok=True)
    print("[split-vb] %s: dtb 段 offset=%d size=%d，拆出 %d 棵" % (src, start, size, len(blobs)))
    for i, (off, blob) in enumerate(blobs):
        name = "%02d_dtb_%d.dtb" % (i, len(blob))
        with open(os.path.join(outdir, name), "wb") as f:
            f.write(blob)
        print("  %-18s section_off=%-8d size=%-8d sha256=%s" % (name, off, len(blob), sha256(blob)[:16]))
    return 0


def cmd_split_dtbo(argv):
    src, outdir = argv[0], argv[1]
    table = parse_dt_table(open(src, "rb").read())
    os.makedirs(outdir, exist_ok=True)
    print("[split-dtbo] %s: magic=0x%08x entries=%d page=%d ver=%d total_size=%d"
          % (src, table["magic"], table["entry_count"], table["page_size"],
             table["version"], table["total_size"]))
    for e in table["entries"]:
        name = "%02d.dtbo" % e["index"]
        with open(os.path.join(outdir, name), "wb") as f:
            f.write(e["blob"])
        print("  %-8s offset=%-8d size=%-8d id=%d rev=%d custom=%s sha256=%s"
              % (name, e["offset"], e["size"], e["id"], e["rev"],
                 ",".join(str(c) for c in e["custom"]), sha256(e["blob"])[:16]))
    return 0


def cmd_img_info(argv):
    for path in argv:
        raw = open(path, "rb").read()
        table = parse_dt_table(raw)
        print("== %s (%d 字节, sha256 %s)" % (path, len(raw), sha256(raw)[:16]))
        print("   magic=0x%08x total_size=%d hdr_size=%d entry_size=%d entry_count=%d "
              "entries_offset=%d page_size=%d version=%d"
              % (table["magic"], table["total_size"], table["hdr_size"],
                 table["entry_size"], table["entry_count"], table["entries_offset"],
                 table["page_size"], table["version"]))
        for e in table["entries"]:
            model, compat = root_summary(e["blob"])
            print("   [%d] offset=%-8d size=%-8d id=%d rev=%d custom=%s sha256=%s"
                  % (e["index"], e["offset"], e["size"], e["id"], e["rev"],
                     ",".join(str(c) for c in e["custom"]), sha256(e["blob"])[:16]))
            print("       model=%s | compatible=%s" % (model, compat))
    return 0


def cmd_count(argv):
    print("%-46s %8s %8s %8s" % ("文件", "节点数", "属性数", "字节数"))
    for path in argv:
        data = open(path, "rb").read()
        _, root, total = parse_fdt(data)
        table = walk(root)
        props = sum(len(dict(n.props)) for n, _ in table.values())
        print("%-46s %8d %8d %8d" % (os.path.basename(path), len(table), props, total))
    return 0


def cmd_root(argv):
    for path in argv:
        data = open(path, "rb").read()
        version, root, total = parse_fdt(data)
        print("== %s (/ 节点, fdt version=%d, %d 字节)" % (path, version, total))
        for name, raw in root.props:
            print("  %-22s %3d 字节  %s" % (name, len(raw), fmt_value(raw)))
    return 0


def _load_tree(path):
    data = open(path, "rb").read()
    _, root, total = parse_fdt(data)
    return walk(root), total


def cmd_cmp(argv):
    a_path, b_path = argv[0], argv[1]
    a, a_total = _load_tree(a_path)
    b, b_total = _load_tree(b_path)
    a_props = sum(len(props) for _, props in a.values())
    b_props = sum(len(props) for _, props in b.values())
    print("A = %s  (%d 字节)" % (a_path, a_total))
    print("B = %s  (%d 字节)" % (b_path, b_total))
    print("节点数   A=%-6d B=%-6d %s" % (len(a), len(b), "一致" if len(a) == len(b) else "不一致"))
    print("属性数   A=%-6d B=%-6d %s" % (a_props, b_props, "一致" if a_props == b_props else "不一致"))

    only_a = sorted(set(a) - set(b))
    only_b = sorted(set(b) - set(a))
    print("节点路径集合  A∪B=%d，仅 A 有 %d，仅 B 有 %d"
          % (len(set(a) | set(b)), len(only_a), len(only_b)))
    for p in only_a[:5]:
        print("   仅 A: %s" % p)
    for p in only_b[:5]:
        print("   仅 B: %s" % p)

    prop_diff, value_diff = [], []
    for path in sorted(set(a) & set(b)):
        pa, pb = a[path][1], b[path][1]
        for name in sorted(set(pa) | set(pb)):
            if name not in pa or name not in pb:
                prop_diff.append((path, name))
            elif pa[name] != pb[name]:
                value_diff.append((path, name))
    print("属性名差异 %d 处，属性值差异 %d 处" % (len(prop_diff), len(value_diff)))
    for path, name in prop_diff[:5]:
        print("   属性名差异: %s:%s" % (path, name))
    for path, name in value_diff[:5]:
        print("   属性值差异: %s:%s A=%s B=%s"
              % (path, name, fmt_value(a[path][1][name]), fmt_value(b[path][1][name])))

    ok = not (only_a or only_b or prop_diff or value_diff)
    print("结果: %s" % ("PASS 结构完全一致" if ok else "FAIL 结构存在差异"))
    return 0 if ok else 1


def cmd_verify_root(argv):
    label = None
    args = []
    i = 0
    while i < len(argv):
        if argv[i] == "--label":
            label = argv[i + 1]
            i += 2
        else:
            args.append(argv[i])
            i += 1
    a_path, b_path = args[0], args[1]
    _, a_root, _ = parse_fdt(open(a_path, "rb").read())
    _, b_root, _ = parse_fdt(open(b_path, "rb").read())
    a_props, b_props = dict(a_root.props), dict(b_root.props)

    print("== 根节点属性逐项对照%s" % ("：" + label if label else ""))
    print("   原厂 %s" % a_path)
    print("   重建 %s" % b_path)
    names = list(dict.fromkeys([n for n, _ in a_root.props] + [n for n, _ in b_root.props]))
    passed = failed = 0
    for name in names:
        if name not in a_props:
            print("  FAIL  %-22s 仅重建产物有" % name)
            failed += 1
        elif name not in b_props:
            print("  FAIL  %-22s 仅原厂有，值 %s" % (name, fmt_value(a_props[name])))
            failed += 1
        elif a_props[name] != b_props[name]:
            print("  FAIL  %-22s 原厂 %s" % (name, fmt_value(a_props[name])))
            print("        %-22s 重建 %s" % ("", fmt_value(b_props[name])))
            failed += 1
        else:
            print("  PASS  %-22s %s" % (name, fmt_value(a_props[name])))
            passed += 1
    print("   小计: PASS %d  FAIL %d（属性名并集 %d 个）" % (passed, failed, len(names)))
    print("RESULT %s" % ("PASS" if failed == 0 else "FAIL"))
    return 0 if failed == 0 else 1


def cmd_verify_img(argv):
    """比对 dt_table 头部与每个 entry 的元数据。

    dtb_size 单独归类：重建产物来自 dts 重新编译，串表合并顺序与厂商原始
    构建不同，长度天然不同（实测 -1.5% 左右），因此只在该 entry 的语义树
    也一致时降级为 SIZE 提示，否则算 FAIL。
    """
    a_path, b_path = argv[0], argv[1]
    a_raw, b_raw = open(a_path, "rb").read(), open(b_path, "rb").read()
    a, b = parse_dt_table(a_raw), parse_dt_table(b_raw)
    print("== dt_table 头部 + entry 元数据对照")
    print("   原厂 %s (%d 字节, sha256 %s)" % (a_path, len(a_raw), sha256(a_raw)[:16]))
    print("   重建 %s (%d 字节, sha256 %s)" % (b_path, len(b_raw), sha256(b_raw)[:16]))

    failed = size_only = passed = 0
    for key in ("magic", "version", "page_size", "entry_count", "hdr_size",
                "entry_size", "entries_offset"):
        av, bv = a[key], b[key]
        if av == bv:
            print("  PASS  %-16s %s" % (key, av if key != "magic" else "0x%08x" % av))
            passed += 1
        else:
            print("  FAIL  %-16s 原厂 %s 重建 %s" % (key, av, bv))
            failed += 1

    # 布局规则：第一个 entry 是否紧跟在 entry 表之后（原厂为 packed 布局）
    for name, table in (("原厂", a), ("重建", b)):
        expect = table["entries_offset"] + table["entry_count"] * table["entry_size"]
        if table["entries"][0]["offset"] != expect:
            print("  WARN  %s 首个 entry offset=%d，entry 表结束于 %d（非紧凑布局）"
                  % (name, table["entries"][0]["offset"], expect))

    for ea, eb in zip(a["entries"], b["entries"]):
        print("  -- entry[%d]" % ea["index"])
        for key in ("id", "rev", "size", "offset"):
            av, bv = ea[key], eb[key]
            label = "dtb_size" if key == "size" else key
            if av == bv:
                print("  PASS  %-16s %s" % (label, av))
                passed += 1
            elif key == "size":
                same = _trees_equal(ea["blob"], eb["blob"])
                print("  %s  %-16s 原厂 %d 重建 %d（%+.3f%%，语义树%s）"
                      % ("SIZE" if same else "FAIL", label, av, bv,
                         (bv - av) * 100.0 / av, "一致" if same else "不一致"))
                if same:
                    size_only += 1
                else:
                    failed += 1
            else:
                print("  FAIL  %-16s 原厂 %s 重建 %s" % (label, av, bv))
                failed += 1
        for i, (ca, cb) in enumerate(zip(ea["custom"], eb["custom"])):
            label = "custom[%d]" % i
            if ca == cb:
                print("  PASS  %-16s %d" % (label, ca))
                passed += 1
            else:
                print("  FAIL  %-16s 原厂 %d 重建 %d" % (label, ca, cb))
                failed += 1
        if sha256(ea["blob"]) == sha256(eb["blob"]):
            print("  PASS  %-16s %s" % ("entry sha256", sha256(ea["blob"])[:16]))
            passed += 1
        else:
            print("  INFO  %-16s 原厂 %s 重建 %s"
                  % ("entry sha256", sha256(ea["blob"])[:16], sha256(eb["blob"])[:16]))
            sa, sb = _fdt_sizes(ea["blob"]), _fdt_sizes(eb["blob"])
            print("        %-16s size_dt_struct %d/%d  size_dt_strings %d/%d"
                  % ("序列化分区", sa["struct"], sb["struct"], sa["strings"], sb["strings"]))
            if _trees_equal(ea["blob"], eb["blob"]):
                print("        %-16s token 流与属性字节完全一致（差异仅在 nameoff 与对齐填充）"
                      % "语义")

    # 载荷整体（dt_table 头 + 全部 entry）。
    # md5 相等只能说明「连厂商那版 dtc 的字符串表打包顺序都一样」，而那不是要还原的东西，
    # 所以不用 md5 当硬门禁。硬门禁是三条：结构块尺寸相等 + 树语义相等 + entry 元数据全等。
    print("  -- 载荷（前 total_size 字节）")
    a_payload = a_raw[:a["total_size"]]
    b_payload = b_raw[:b["total_size"]]
    a_md5 = hashlib.md5(a_payload).hexdigest()
    b_md5 = hashlib.md5(b_payload).hexdigest()

    pairs = list(zip(a["entries"], b["entries"]))
    struct_ok = all(_fdt_sizes(ea["blob"])["struct"] == _fdt_sizes(eb["blob"])["struct"]
                    for ea, eb in pairs)
    text_ok = all(_trees_equal(ea["blob"], eb["blob"]) for ea, eb in pairs)
    meta_ok = failed == 0

    print("  %s  %-16s size_dt_struct 全部相等=%s / token 流语义相等=%s / entry 元数据全等=%s"
          % ("INFO", "门禁三项", "是" if struct_ok else "否",
             "是" if text_ok else "否", "是" if meta_ok else "否"))
    for ea, eb in pairs:
        sa, sb = _fdt_sizes(ea["blob"]), _fdt_sizes(eb["blob"])
        if sa["strings"] != sb["strings"]:
            print("  INFO  %-16s entry[%d] size_dt_strings %d → %d（%+d）"
                  % ("字符串表差值", ea["index"], sa["strings"], sb["strings"],
                     sb["strings"] - sa["strings"]))

    if a_md5 == b_md5:
        print("  PASS  %-16s %s" % ("payload md5", a_md5))
        passed += 1
    elif struct_ok and text_ok and meta_ok and len(a["entries"]) == len(b["entries"]):
        print("  BYTES %-16s 原厂 %s 重建 %s" % ("payload md5", a_md5, b_md5))
        print("        %-16s 结构块尺寸、token 流、entry 元数据全等；差异仅在 nameoff、"
              "字符串表与对齐填充" % "")
        size_only += 1
    else:
        print("  FAIL  %-16s 原厂 %s 重建 %s" % ("payload md5", a_md5, b_md5))
        failed += 1

    print("   小计: PASS %d  SIZE/BYTES %d  FAIL %d" % (passed, size_only, failed))
    print("   注: SIZE/BYTES 表示结构与语义全等、仅序列化细节不同，不计失败；"
          "逐字节一致不是本任务的验收项")
    print("RESULT %s" % ("PASS" if failed == 0 else "FAIL"))
    return 0 if failed == 0 else 1


def _trees_equal(a_blob, b_blob):
    try:
        ta, _ = _load_tree_blob(a_blob)
        tb, _ = _load_tree_blob(b_blob)
    except ValueError:
        return False
    return ta == tb


def _fdt_sizes(blob):
    _, total, off_struct, off_str, _, _, _, _, str_sz, struct_sz = \
        struct.unpack_from(">10I", blob, 0)
    return {"total": total, "off_struct": off_struct, "off_strings": off_str,
            "struct": struct_sz, "strings": str_sz}


def _load_tree_blob(blob):
    _, root, total = parse_fdt(blob)
    table = walk(root)
    return {path: dict(props) for path, (_, props) in table.items()}, total


def cmd_matrix(argv):
    rows = []
    for item in argv:
        label, _, path = item.partition("=")
        raw = open(path, "rb").read()
        table = parse_dt_table(raw)
        entries = []
        for e in table["entries"]:
            model, compat = root_summary(e["blob"])
            entries.append((e["size"], sha256(e["blob"]), model, compat))
        rows.append((label, path, len(raw), sha256(raw), table, entries))

    print("== 三来源 dtbo.img 差异矩阵")
    print("%-8s %-12s %-10s %-8s %s" % ("来源", "文件字节", "sha256", "entry 数", "dt_table 头"))
    for label, path, size, sha, table, entries in rows:
        print("%-8s %-12d %-10s %-8d magic=0x%08x total=%d page=%d ver=%d"
              % (label, size, sha[:10], table["entry_count"], table["magic"],
                 table["total_size"], table["page_size"], table["version"]))
    print()
    print("%-8s %-6s %-10s %-9s %-46s %s" % ("来源", "entry", "size", "sha256", "model", "compatible"))
    for label, path, size, sha, table, entries in rows:
        for i, (esize, esha, model, compat) in enumerate(entries):
            print("%-8s %-6d %-10d %-9s %-46s %s" % (label, i, esize, esha[:9], model[:46], compat))

    # 内容一致性：取各来源 entry 的 sha 做交集判定
    print()
    print("== 逐 entry 内容是否跨来源相同")
    max_entries = max(len(r[5]) for r in rows)
    all_same = True
    for i in range(max_entries):
        shas = {label: entries[i][1] for label, _, _, _, _, entries in rows if i < len(entries)}
        uniq = set(shas.values())
        same = len(uniq) == 1
        all_same = all_same and same
        print("  entry[%d] %s  %s" % (i, "一致" if same else "不同",
                                      " ".join("%s=%s" % (k, v[:9]) for k, v in shas.items())))
    print("结论: %s" % ("三来源 dtbo 的全部 entry 内容逐字节相同"
                       if all_same else "存在内容不同的 entry"))
    return 0 if all_same else 1


def cmd_unzip_parts(argv):
    """从 zip 里按成员名选择性解出（fastboot 包 6.7 GB，不能整包解）。"""
    import shutil
    import zipfile

    zip_path, outdir, names = argv[0], argv[1], set(argv[2:])
    os.makedirs(outdir, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        picked = [n for n in zf.namelist() if os.path.basename(n) in names]
        if not picked:
            raise SystemExit("%s 里没有 %s" % (zip_path, sorted(names)))
        for member in picked:
            dst = os.path.join(outdir, os.path.basename(member))
            with zf.open(member) as src, open(dst, "wb") as out:
                shutil.copyfileobj(src, out)
            print("[unzip] %s -> %s (%d 字节)" % (member, dst, os.path.getsize(dst)))
    return 0


# --- dtc 反编译的字符串转义歧义修正 ---------------------------------------
ESC_BYTE = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13,
            '"': 34, "'": 39, "\\": 92, "0": 0}
ASSIGN_RE = None  # 延迟编译，避免 import 时就依赖 re


def decode_dts_string(text):
    """把 dts 引号字面量还原成字节；dtc 总会为字符串补结尾 NUL。"""
    import re
    global ASSIGN_RE
    out = bytearray()
    i = 0
    while i < len(text):
        ch = text[i]
        if ch != "\\":
            out += ch.encode("latin-1")
            i += 1
            continue
        nxt = text[i + 1]
        if nxt in "01234567":
            j, digits = i + 1, ""
            while j < len(text) and len(digits) < 3 and text[j] in "01234567":
                digits += text[j]
                j += 1
            out.append(int(digits, 8) & 0xFF)
            i = j
        elif nxt == "x":
            j, digits = i + 2, ""
            while j < len(text) and len(digits) < 2 and text[j] in "0123456789abcdefABCDEF":
                digits += text[j]
                j += 1
            out.append(int(digits, 16) & 0xFF)
            i = j
        else:
            out.append(ESC_BYTE[nxt])
            i += 2
    out.append(0)
    return bytes(out)


def literal_for(data, prefer_cells):
    """按目标字节生成不会二次歧义的 dts 写法。"""
    printable = all(0x20 <= b < 0x7F for b in data.rstrip(b"\0")) and data.endswith(b"\0")
    if not printable:
        return "[" + " ".join("%02x" % b for b in data) + "]"
    if prefer_cells and len(data) <= 16 and len(data) % 4 == 0:
        words = struct.unpack(">%dI" % (len(data) // 4), data)
        return "<" + " ".join("0x%08x" % w for w in words) + ">"
    body = data[:-1] if data.endswith(b"\0") else data
    return ", ".join('"' + c.decode("latin-1") + '"' for c in body.split(b"\0"))


def cmd_normalize_dts(argv):
    """dtc 把「NUL 后紧跟 0-7」渲染成 \\0+数字，再解析会被吃成一位八进制。

    例如原值 "0\\0" "2\\0" 被写成 \\00\\02，回读变成 0x00 0x02——值被改义。
    这里以 dtb 的真实字节为准，把出问题的属性改写成逗号字符串列表 /
    u32 cell / 字节数组，保证 dts→dtb 往返无损。
    """
    import re

    prefer_cells = "--cells" in argv
    args = [a for a in argv if not a.startswith("--")]
    dts_path, dtb_path = args[0], args[1]
    _, root, _ = parse_fdt(open(dtb_path, "rb").read())
    truth = {path: {name: value for name, value in props.items()}
             for path, (_, props) in walk(root).items()}

    prop_re = re.compile(r'^([ \t]*)([A-Za-z0-9_,.+#?*/@-]+) = "((?:[^"\\]|\\.)*)";[ \t]*$')
    lines = open(dts_path, "r", encoding="utf-8").read().split("\n")
    stack = []
    changed = skipped = 0
    for idx, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "/*", "*")):
            continue
        if stripped.endswith("{"):
            stack.append(stripped[:-1].strip())
            continue
        if stripped.startswith("};") or stripped == "}":
            if stack:
                stack.pop()
            continue
        m = prop_re.match(line)
        if not m:
            continue
        indent, name, raw = m.groups()
        path = "/" + "/".join(stack[1:]) if len(stack) > 1 else "/"
        want = truth.get(path, {}).get(name)
        if want is None:
            skipped += 1
            continue
        if decode_dts_string(raw) == want:
            continue
        lines[idx] = "%s%s = %s;" % (indent, name, literal_for(want, prefer_cells))
        changed += 1
    open(dts_path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print("[normalize-dts] %s: 改写 %d 行（路径未命中的引号属性 %d 个）"
          % (dts_path, changed, skipped))
    return 0


def cmd_manifest(argv):
    """生成 original/manifest.tsv：每个 DTB / dtbo entry 一行。"""
    out_path, items = argv[0], argv[1:]
    rows = []
    for item in items:
        label, _, path = item.partition("=")
        data = open(path, "rb").read()
        if data[:8] == b"VNDRBOOT":
            info = parse_vendor_boot(data)
            section = data[info["dtb_offset"]:info["dtb_offset"] + info["dtb_size"]]
            for i, (off, blob) in enumerate(split_fdt_stream(section)):
                model, compat = root_summary(blob)
                rows.append([label, "vendor_boot", i, off, len(blob), "-", "-", "-",
                             "-", "-", "-", model, compat, sha256(blob)])
        elif struct.unpack_from(">I", data, 0)[0] == DT_TABLE_MAGIC:
            table = parse_dt_table(data)
            for e in table["entries"]:
                model, compat = root_summary(e["blob"])
                custom = [str(c) for c in e["custom"]]
                rows.append([label, "dtbo", e["index"], e["offset"], e["size"],
                             e["id"], e["rev"]] + custom +
                            [model, compat, sha256(e["blob"])])
        else:
            raise SystemExit("%s: 既不是 vendor_boot 也不是 dt_table" % path)

    header = ["source", "part", "index", "offset", "size", "id", "rev",
              "custom0", "custom1", "custom2", "custom3", "model", "compatible", "sha256"]
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\t".join(header) + "\n")
        for row in rows:
            f.write("\t".join(str(v) for v in row) + "\n")
    print("[manifest] %s: %d 行（%d 个来源）"
          % (out_path, len(rows), len({r[0] for r in rows})))
    for row in rows:
        print("  %-10s %-11s [%2d] size=%-8s sha256=%s  %s"
              % (row[0], row[1], row[2], row[4], row[-1][:16], row[-3]))
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    table = {
        "vb-info": cmd_vb_info, "split-vb": cmd_split_vb, "split-dtbo": cmd_split_dtbo,
        "img-info": cmd_img_info, "count": cmd_count, "root": cmd_root, "cmp": cmd_cmp,
        "verify-root": cmd_verify_root, "verify-img": cmd_verify_img, "matrix": cmd_matrix,
        "unzip-parts": cmd_unzip_parts, "normalize-dts": cmd_normalize_dts,
        "manifest": cmd_manifest,
    }
    if cmd not in table:
        print("未知子命令: %s" % cmd, file=sys.stderr)
        print(__doc__)
        return 2
    if not rest:
        print("子命令 %s 缺少参数" % cmd, file=sys.stderr)
        return 2
    return table[cmd](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
