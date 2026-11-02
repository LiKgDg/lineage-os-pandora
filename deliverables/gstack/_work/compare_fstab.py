"""Compare fstab.qcom records across LOS/stock, vendor/etc vs first_stage."""
import sys, os

FILES = {
    "LOS_vendor_etc": "los_vendor_etc_fstab.qcom",
    "LOS_first_stage": "los_first_stage_fstab.qcom",
    "STOCK_first_stage": "stock_first_stage_fstab.qcom",
}
ORDER = ["LOS_vendor_etc", "LOS_first_stage", "STOCK_first_stage"]


def parse(path):
    recs = []
    with open(path, "rb") as f:
        for lineno, raw in enumerate(f.read().decode("utf-8", "replace").splitlines(), 1):
            s = raw.strip()
            if not s or s.startswith("#"):
                continue
            parts = s.split()
            if len(parts) < 5:
                continue
            recs.append(dict(src=parts[0], mnt=parts[1], typ=parts[2],
                             mnt_flags=parts[3], fs_mgr_flags=parts[4],
                             lineno=lineno, raw=raw.rstrip()))
    return recs


def key(r):
    return (r["mnt"], r["src"])


def main():
    data = {k: parse(v) for k, v in FILES.items()}
    for k in ORDER:
        print(f"# {k}: {len(data[k])} records")

    # index by mount point
    bymnt = {}
    for k in ORDER:
        for r in data[k]:
            bymnt.setdefault(r["mnt"], {})[k] = r

    print("\n## Records by mount point\n")
    print("| mount | LOS vendor/etc | LOS first_stage | stock first_stage | note |")
    print("|---|---|---|---|---|")
    for mnt in bymnt:
        cells = []
        notes = []
        present = [k for k in ORDER if k in bymnt[mnt]]
        for k in ORDER:
            if k not in bymnt[mnt]:
                cells.append("—")
            else:
                cells.append("yes")
        # compare LOS vendor vs stock first_stage for same mnt
        a = bymnt[mnt].get("LOS_vendor_etc")
        b = bymnt[mnt].get("STOCK_first_stage")
        if a and b:
            if a["raw"] != b["raw"]:
                if a["fs_mgr_flags"] != b["fs_mgr_flags"]:
                    notes.append("fs_mgr_flags differ")
                if a["mnt_flags"] != b["mnt_flags"]:
                    notes.append("mnt_flags differ")
                if a["typ"] != b["typ"]:
                    notes.append("type differ")
                if a["src"] != b["src"]:
                    notes.append("src differ")
        elif a and not b:
            notes.append("LOS-only")
        elif b and not a:
            notes.append("stock-only")
        print(f"| `{mnt}` | {cells[0]} | {cells[1]} | {cells[2]} | {'; '.join(notes)} |")

    print("\n\n## /data line, all sources verbatim\n")
    for k in ORDER:
        for r in data[k]:
            if r["mnt"] == "/data":
                print(f"[{k}] line {r['lineno']}")
                print(f"  src        : {r['src']}")
                print(f"  type       : {r['typ']}")
                print(f"  mnt_flags  : {r['mnt_flags']}")
                print(f"  fs_mgr     : {r['fs_mgr_flags']}")
                print()

    print("\n## /data flag set difference (LOS vendor/etc vs stock first_stage)\n")
    a = next(r for r in data["LOS_vendor_etc"] if r["mnt"] == "/data")
    b = next(r for r in data["STOCK_first_stage"] if r["mnt"] == "/data")
    for field in ("mnt_flags", "fs_mgr_flags"):
        sa = set(a[field].split(","))
        sb = set(b[field].split(","))
        print(f"### {field}")
        print(f"  stock-only : {sorted(sb - sa) or '(none)'}")
        print(f"  LOS-only   : {sorted(sa - sb) or '(none)'}")
        print(f"  common     : {len(sa & sb)} flags")
        print()

    print("\n## /metadata line, all sources verbatim\n")
    for k in ORDER:
        for r in data[k]:
            if r["mnt"] == "/metadata":
                print(f"[{k}] {r['raw']}")
    print()
    print("## /metadata flag set difference\n")
    a = next(r for r in data["LOS_vendor_etc"] if r["mnt"] == "/metadata")
    b = next(r for r in data["STOCK_first_stage"] if r["mnt"] == "/metadata")
    for field in ("mnt_flags", "fs_mgr_flags"):
        sa = set(a[field].split(","))
        sb = set(b[field].split(","))
        print(f"### {field}: stock-only={sorted(sb-sa) or '(none)'} LOS-only={sorted(sa-sb) or '(none)'}")


if __name__ == "__main__":
    main()
