#!/usr/bin/env python3
"""So khop 2 file (HW output vs Golden) trong terminal.

Mac dinh hieu moi dong la 1 byte hex int8 co dau (dinh dang .hex cua du an:
1 byte/dong, 2 chu so hex). Bo qua dong trong va dong comment '#'.

Vi du:
    python script/cmp_hex.py tb/data/golden_ofm.hex tb/data/hw_out.hex
    python script/cmp_hex.py golden_ofm.hex hw_out.hex --dir tb/scripts
    python script/cmp_hex.py a.hex b.hex --width 4            # word 4-byte
    python script/cmp_hex.py a.hex b.hex --unsigned --tol 1   # cho phep lech 1
    python script/cmp_hex.py a.txt b.txt --text               # diff tho theo dong

Exit code: 0 neu khop 100%, 1 neu co mismatch / loi (tien cho script & CI).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def load_vals(path: Path, width: int, signed: bool) -> list[int]:
    """Doc file hex: moi dong 1 phan tu, bo qua dong trong / comment '#'."""
    vals: list[int] = []
    for lineno, line in enumerate(path.read_text(encoding="utf-8", errors="ignore").splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        s = s.split()[0]  # lay token dau neu dong co nhieu cot
        try:
            v = int(s, 16)
        except ValueError:
            sys.exit(f"[ERROR] {path}:{lineno}: khong phai hex hop le: {s!r} "
                     f"(dung --text neu la file van ban dang bang)")
        if signed:
            bits = width * 8
            if v >= (1 << (bits - 1)):
                v -= (1 << bits)
        vals.append(v)
    return vals


def load_lines(path: Path) -> list[str]:
    return [ln.rstrip("\n") for ln in path.read_text(encoding="utf-8", errors="ignore").splitlines()]


def fmt(v: int, width: int) -> str:
    """Hien hex (bu 2) kem gia tri thap phan."""
    mask = (1 << (width * 8)) - 1
    return f"{v & mask:0{width*2}x}({v})"


def compare_hex(a: Path, b: Path, args) -> int:
    va = load_vals(a, args.width, not args.unsigned)
    vb = load_vals(b, args.width, not args.unsigned)

    n = min(len(va), len(vb))
    mismatches = []
    for i in range(n):
        if abs(va[i] - vb[i]) > args.tol:
            mismatches.append(i)

    print(f"[CMP] {a.name}  vs  {b.name}")
    if len(va) != len(vb):
        print(f"  [WARN] So phan tu khac nhau: {a.name}={len(va)}, {b.name}={len(vb)} "
              f"(so {n} phan tu dau)")
    match = n - len(mismatches)
    acc = (match / n * 100) if n else 0.0
    print(f"  Elements: {n} | Match: {match} | Mismatch: {len(mismatches)} | Accuracy: {acc:.2f}%")
    if args.tol:
        print(f"  (tolerance = {args.tol})")

    for i in mismatches[: args.max]:
        print(f"  idx {i:>5}: A={fmt(va[i], args.width)}  B={fmt(vb[i], args.width)}")
    if len(mismatches) > args.max:
        print(f"  ... va {len(mismatches) - args.max} mismatch nua (tang --max de xem them)")

    if len(va) != len(vb) or mismatches:
        print(f"[FAIL] {len(mismatches)} mismatch(es)"
              + ("" if len(va) == len(vb) else " + lech so phan tu") + ".")
        return 1
    print("[PASS] Hai file khop 100%.")
    return 0


def compare_text(a: Path, b: Path, args) -> int:
    la, lb = load_lines(a), load_lines(b)
    n = min(len(la), len(lb))
    mismatches = [i for i in range(n) if la[i] != lb[i]]

    print(f"[CMP/text] {a.name}  vs  {b.name}")
    if len(la) != len(lb):
        print(f"  [WARN] So dong khac nhau: {a.name}={len(la)}, {b.name}={len(lb)}")
    print(f"  Lines: {n} | Match: {n - len(mismatches)} | Mismatch: {len(mismatches)}")
    for i in mismatches[: args.max]:
        print(f"  line {i+1:>5}:")
        print(f"    A| {la[i]}")
        print(f"    B| {lb[i]}")
    if len(la) != len(lb) or mismatches:
        print(f"[FAIL] {len(mismatches)} dong khac.")
        return 1
    print("[PASS] Hai file giong het.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="So khop 2 file HW output vs Golden.")
    p.add_argument("file_a", help="File thu nhat (vd HW output)")
    p.add_argument("file_b", help="File thu hai (vd Golden)")
    p.add_argument("--dir", help="Thu muc chung chua 2 file (noi voi ten file)")
    p.add_argument("--width", type=int, default=1, help="So byte moi phan tu (mac dinh 1)")
    p.add_argument("--unsigned", action="store_true", help="Hieu gia tri khong dau (mac dinh signed)")
    p.add_argument("--tol", type=int, default=0, help="Nguong sai so cho phep (mac dinh 0)")
    p.add_argument("--max", type=int, default=50, help="So mismatch in toi da (mac dinh 50)")
    p.add_argument("--text", action="store_true", help="So sanh tho theo tung dong (file .txt)")
    args = p.parse_args()

    base = Path(args.dir) if args.dir else Path(".")
    a = base / args.file_a
    b = base / args.file_b
    for f in (a, b):
        if not f.is_file():
            sys.exit(f"[ERROR] Khong tim thay file: {f}")

    if args.text:
        return compare_text(a, b, args)
    return compare_hex(a, b, args)


if __name__ == "__main__":
    raise SystemExit(main())
