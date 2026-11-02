#!/usr/bin/env python3
"""刷机前门禁 G1：内核 ↔ 模块 KMI 一致性校验（纯离线，零风险）。

起因：18:25 那份 LOS 构建的 kernel 是 6.12.69（原厂二进制），但 vendor_boot
ramdisk 里 461 个 .ko 有 405 个是按 6.12.23 编译的。CONFIG_MODVERSIONS=y 时
check_modstruct_version() 无条件比对 module_layout 的 CRC，不一致即 -ENOEXEC。
结果：vendor_boot 的 modules.load 150 条可加载 0 条 —— 刷了必然失败，
而这一步本可以离线查出，不必消耗四次刷机。

用法：
    python check_kmi.py <images_dir> [--deep]
        <images_dir> 需含 boot.img / vendor_boot.img
        可选 vendor_dlkm.img / system_dlkm.img
        --deep 对 dlkm 分区逐文件读 ELF 取 CRC（准，但纯 Python 需数分钟）

判据（任一不满足即 exit 1，拒绝刷机）：
    1. modules.load 引用的模块文件必须存在；
    2. 每个被引用模块的 module_layout CRC 必须等于内核侧期望值；
    3. 期望值 = 内核映像中「唯一命中」的 4 字节 LE 值（无需符号表）。
"""
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from bootimg import parse_boot, parse_vendor_boot          # noqa: E402
from lz4legacy import decompress_any                        # noqa: E402
from erofsmini import Erofs                                 # noqa: E402
from ext4mini import Ext4                                   # noqa: E402

KMI_PREFIX = b"6.12.69-android16-6"      # 由内核 banner 反推，运行时覆盖


# ---------- cpio ----------
def parse_cpio(data):
    i = 0
    while True:
        if data[i:i + 6] not in (b"070701", b"070702"):
            j = data.find(b"070701", i)
            if j < 0:
                return
            i = j
        hdr = data[i:i + 110]
        filesize = int(hdr[54:62], 16)
        namesize = int(hdr[94:102], 16)
        name = data[i + 110:i + 110 + namesize - 1].decode("utf8", "replace")
        off = i + (110 + namesize + 3) // 4 * 4
        yield name, data[off:off + filesize]
        i = (off + filesize + 3) // 4 * 4
        if name == "TRAILER!!!":
            return


# ---------- module introspection ----------
def module_info(blob):
    """返回 (vermagic, module_layout_crc)。"""
    m = re.search(rb"vermagic=([^\x00\n]+)", blob)
    vermagic = m.group(1).decode("utf8", "replace") if m else None
    j = blob.find(b"module_layout\x00")
    crc = struct.unpack("<Q", blob[j - 8:j])[0] if j >= 8 else None
    return vermagic, crc


def collect_vendor_boot(path):
    info = parse_vendor_boot(path)
    with open(path, "rb") as f:
        f.seek(info["vendor_ramdisk_off"])
        raw = f.read(info["vendor_ramdisk_size"])
    data, how = decompress_any(raw)
    kos, loads = {}, {}
    for name, body in parse_cpio(data):
        if name.endswith(".ko"):
            kos[name.split("/")[-1]] = module_info(body)
        elif name.endswith("modules.load"):
            loads[name] = body.decode("utf8", "replace")
    return info, kos, loads, how


def open_fs(path):
    """自动判别 EROFS / ext4（本项目 dlkm 镜像是 ext4，super 内是 erofs）。"""
    with open(path, "rb") as f:
        head = f.read(4096)
    if len(head) >= 1028 and head[1024:1028] == b"\xe2\xe1\xf5\xe0":
        return Erofs(path), "erofs"
    if len(head) >= 1082 and head[1080:1082] == b"\x53\xef":
        return Ext4(path), "ext4"
    raise ValueError(f"{os.path.basename(path)}: 既不是 EROFS 也不是 ext4")


def _walk(fs, base, prefix=""):
    """递归列出相对路径。listdir 返回 None/抛异常 ⇒ 该路径是文件。"""
    try:
        names = fs.listdir(base)
    except Exception:                                        # noqa: BLE001
        return []
    if not names:
        return []
    out = []
    for fn in names:
        p = f"{base}/{fn}"
        rel = f"{prefix}{fn}"
        try:
            sub = fs.listdir(p)
        except Exception:                                    # noqa: BLE001
            sub = None
        if sub:
            out += _walk(fs, p, rel + "/")
        else:
            out.append(rel)
    return out


def dlkm_loads(path):
    """只读 modules.load（小文件，快）与其所在目录。"""
    fs, kind = open_fs(path)
    out = {}
    try:
        vers = fs.listdir("/lib/modules") or []
    except Exception:                                        # noqa: BLE001
        vers = []
    for ver in vers:
        body = fs.cat(f"/lib/modules/{ver}/modules.load")
        if body:
            out[f"{os.path.basename(path)}:/lib/modules/{ver}/modules.load"] = \
                body.decode("utf8", "replace")
    return out, fs, kind


def dlkm_deep(path):
    """逐文件读 ELF（慢），返回 {相对路径: (vermagic, crc)}。"""
    fs, _ = open_fs(path)
    kos = {}
    try:
        vers = fs.listdir("/lib/modules") or []
    except Exception:                                        # noqa: BLE001
        return kos
    for ver in vers:
        base = f"/lib/modules/{ver}"
        for rel in _walk(fs, base):
            if not rel.endswith(".ko"):
                continue
            blob = fs.cat(f"{base}/{rel}")
            if blob:
                kos[rel] = module_info(blob)
                kos.setdefault(os.path.basename(rel), kos[rel])
    return kos


def expected_crc_from_kernel(kernel, candidates):
    """在 Image 中找「唯一命中」的候选 CRC，作为 module_layout 期望值。"""
    scored = sorted((kernel.count(struct.pack("<I", v & 0xFFFFFFFF)), v)
                    for v in candidates if v is not None)
    hits = [s for s in scored if s[0] == 1]
    return (hits[0][1] if hits else None), scored


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    deep = "--deep" in sys.argv
    if not args:
        print(__doc__)
        return 2
    d = args[0]
    boot = os.path.join(d, "boot.img")
    vboot = os.path.join(d, "vendor_boot.img")
    if not (os.path.exists(boot) and os.path.exists(vboot)):
        print(f"缺少 boot.img / vendor_boot.img：{d}")
        return 2

    # 1) 内核
    bi = parse_boot(boot)
    with open(boot, "rb") as f:
        f.seek(bi["kernel_off"])
        kernel = f.read(bi["kernel_size"])
    m = re.search(rb"Linux version (\S+)", kernel)
    banner = m.group(1).decode() if m else "UNKNOWN"
    kmi = "-".join(banner.split("-")[:2]).encode()           # 6.12.69-android16-6

    # 2) vendor_boot（精确：逐条核对存在性 + CRC）
    _, vkos, vloads, how = collect_vendor_boot(vboot)
    all_crc = {c for _, c in vkos.values()}
    sources = [("vendor_boot", vkos, vloads)]

    # 3) dlkm（默认快速普查；--deep 逐文件）
    dlkm_meta = {}
    for name in ("vendor_dlkm.img", "system_dlkm.img"):
        p = os.path.join(d, name)
        if not os.path.exists(p):
            continue
        loads, _, kind = dlkm_loads(p)
        if deep:
            kos = dlkm_deep(p)
            all_crc |= {c for _, c in kos.values()}
            sources.append((name, kos, loads))
        else:
            with open(p, "rb") as f:
                img = f.read()
            names = {n.decode() for n in re.findall(rb"[A-Za-z0-9_.+-]+\.ko", img)}
            dlkm_meta[name] = dict(kind=kind,
                                   total=img.count(b"vermagic="),
                                   bad=img.count(b"vermagic=") - img.count(b"vermagic=" + kmi),
                                   names=names)
            sources.append((name, {}, loads))

    expected, scored = expected_crc_from_kernel(kernel, all_crc)

    print(f"\n内核 banner : {banner}")
    print(f"期望 KMI    : {kmi.decode()}")
    print(f"ramdisk     : {how}；模块 {len(vkos)}；modules.load {len(vloads)}")
    print(f"候选 CRC 在内核中的命中次数: {scored}")
    print(f"期望 module_layout CRC: {hex(expected) if expected else '未确定'}\n")

    fail = 0
    for src, kos, loads in sources:
        for lname, body in loads.items():
            entries = [l.strip() for l in body.splitlines()
                       if l.strip() and not l.startswith("#")]
            if src in dlkm_meta and not deep:
                meta = dlkm_meta[src]
                missing = [e for e in entries
                           if os.path.basename(e) not in meta["names"]]
                ok = "n/a"
                bad = "n/a(普查)"
                verdict = "PASS" if meta["bad"] == 0 and not missing else "FAIL"
            else:
                missing = [e for e in entries if e not in kos]
                bad = [e for e in entries if e in kos and kos[e][1] != expected]
                ok = len(entries) - len(missing) - len(bad)
                verdict = "PASS" if not missing and not bad else "FAIL"
            if verdict == "FAIL":
                fail += 1
            print(f"[{verdict}] {src} :: {lname}")
            print(f"       条目 {len(entries)}｜可加载 {ok}｜CRC 不符 "
                  f"{bad if isinstance(bad, str) else len(bad)}｜文件缺失 {len(missing)}")
            if src in dlkm_meta and not deep:
                meta = dlkm_meta[src]
                print(f"       vermagic 普查：共 {meta['total']} 个模块，"
                      f"{meta['bad']} 个不是 {kmi.decode()}（{meta['kind']}）")
            if missing:
                print(f"       缺失: {missing[:8]}{' ...' if len(missing) > 8 else ''}")
            if not isinstance(bad, str) and bad:
                vm = sorted({kos[e][0] for e in bad if kos[e][0]})
                print(f"       不符样例: {bad[:5]}")
                print(f"       其 vermagic: {vm[:2]}")

    print("\n" + ("G1 通过：模块与内核一致，可刷。" if not fail
                  else f"G1 失败：{fail} 个 modules.load 不可全量加载 —— 拒绝刷机。"))
    return 0 if not fail else 1


if __name__ == "__main__":
    sys.exit(main())
