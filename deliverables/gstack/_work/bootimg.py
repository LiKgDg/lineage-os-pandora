"""Parse Android boot.img / vendor_boot.img headers and extract ramdisk segments."""
import struct, os

def parse_vendor_boot(path):
    with open(path, "rb") as f:
        head = f.read(4096)
        assert head[:8] == b"VNDRBOOT", head[:8]
        hv = struct.unpack_from("<I", head, 8)[0]
        page = struct.unpack_from("<I", head, 12)[0]
        kernel_addr = struct.unpack_from("<I", head, 16)[0]
        ramdisk_addr = struct.unpack_from("<I", head, 20)[0]
        vrd_size = struct.unpack_from("<I", head, 24)[0]
        cmdline = head[28:28+2048].split(b"\0")[0]
        tags_addr = struct.unpack_from("<I", head, 2076)[0]
        name = head[2080:2096].split(b"\0")[0]
        header_size = struct.unpack_from("<I", head, 2096)[0]
        dtb_size = struct.unpack_from("<I", head, 2100)[0]
        dtb_addr = struct.unpack_from("<Q", head, 2104)[0]
        info = dict(header_version=hv, page_size=page, kernel_addr=kernel_addr,
                    ramdisk_addr=ramdisk_addr, vendor_ramdisk_size=vrd_size,
                    cmdline=cmdline.decode("utf-8","replace"), name=name.decode("utf-8","replace"),
                    header_size=header_size, dtb_size=dtb_size, dtb_addr=dtb_addr,
                    file_size=os.path.getsize(path))
        if hv >= 4:
            tbl_size = struct.unpack_from("<I", head, 2112)[0]
            tbl_num = struct.unpack_from("<I", head, 2116)[0]
            tbl_ent = struct.unpack_from("<I", head, 2120)[0]
            bootconfig_size = struct.unpack_from("<I", head, 2124)[0]
            info.update(vendor_ramdisk_table_size=tbl_size, table_entry_num=tbl_num,
                        table_entry_size=tbl_ent, bootconfig_size=bootconfig_size)
        # segments start at page boundary
        off = page
        info["vendor_ramdisk_off"] = off
        off += vrd_size
        info["dtb_off"] = off
        off += dtb_size
        if hv >= 4:
            info["table_off"] = off
            off += info["vendor_ramdisk_table_size"]
            info["bootconfig_off"] = off
        return info

def read_segment(path, off, size, out):
    with open(path, "rb") as f:
        f.seek(off)
        d = f.read(size)
    with open(out, "wb") as g:
        g.write(d)
    return len(d)

def parse_boot(path):
    """boot_img_hdr_v3/v4: page is always 4096."""
    with open(path, "rb") as f:
        head = f.read(4096)
        assert head[:8] == b"ANDROID!", head[:8]
        kernel_size = struct.unpack_from("<I", head, 8)[0]
        ramdisk_size = struct.unpack_from("<I", head, 12)[0]
        os_version = struct.unpack_from("<I", head, 16)[0]
        header_size = struct.unpack_from("<I", head, 20)[0]
        header_version = struct.unpack_from("<I", head, 40)[0]
        cmdline = head[44:44+1536].split(b"\0")[0]
        page = 4096
        info = dict(header_version=header_version, kernel_size=kernel_size,
                    ramdisk_size=ramdisk_size, os_version=os_version,
                    header_size=header_size, page_size=page,
                    cmdline=cmdline.decode("utf-8", "replace"),
                    file_size=os.path.getsize(path))
        off = page
        info["kernel_off"] = off
        off += kernel_size
        info["ramdisk_off"] = off
        return info
