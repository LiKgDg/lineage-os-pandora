"""Extract .ko modules from a cpio ramdisk and tally vermagic + module_layout CRC."""
import sys, os, struct, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cpiomini

MODNAME_LEN = 56  # MODULE_NAME_LEN for 64-bit


def ko_info(data):
    vm = None
    i = data.find(b"vermagic=")
    if i >= 0:
        j = data.find(b"\x00", i)
        vm = data[i + 9:j].decode("utf-8", "replace")
    crc = None
    k = data.find(b"module_layout\x00")
    if k >= 8:
        crc = struct.unpack_from("<Q", data, k - 8)[0]
    return vm, crc


def scan_cpio(path, label):
    blob = open(path, "rb").read()
    kos = {}
    for e in cpiomini.parse_cpio(blob):
        n = e["name"]
        if n.endswith(".ko"):
            kos[n] = e["data"]
    vm_c = collections.Counter()
    crc_c = collections.Counter()
    crc_by_vm = collections.defaultdict(collections.Counter)
    for n, d in kos.items():
        vm, crc = ko_info(d)
        vm_c[vm] += 1
        crc_c[crc] += 1
        crc_by_vm[vm][crc] += 1
    print(f"### {label}: {len(kos)} .ko modules")
    print("  vermagic distribution:")
    for vm, c in vm_c.most_common():
        print(f"    {c:4d}  {vm}")
    print("  module_layout CRC distribution:")
    for crc, c in crc_c.most_common():
        print(f"    {c:4d}  0x{crc:016x}" if crc is not None else f"    {c:4d}  None")
    print("  CRC by vermagic:")
    for vm, cc in crc_by_vm.items():
        print(f"    {vm}: " + ", ".join(f"0x{k:016x}×{v}" if k is not None else f"None×{v}" for k, v in cc.most_common()))
    # modules.load
    for e in cpiomini.parse_cpio(blob):
        if e["name"].endswith("modules.load"):
            lines = [l.strip() for l in e["data"].decode("utf-8", "replace").splitlines()]
            lines = [l for l in lines if l and not l.startswith("#")]
            print(f"  {e['name']}: {len(lines)} entries")
            # how many point at modules whose CRC != majority?
            return kos, vm_c, crc_c, e["name"], lines
    return kos, vm_c, crc_c, None, []


if __name__ == "__main__":
    for p, lab in (("los_vendor_ramdisk.cpio", "LOS vendor_boot ramdisk"),
                   ("stock_vendor_ramdisk.cpio", "STOCK vendor_boot ramdisk")):
        scan_cpio(p, lab)
        print()
