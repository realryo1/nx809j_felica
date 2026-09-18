#!/usr/bin/env python3
"""Patch AOSP libnfc_nci_jni.so so eSE Type-F CE listen is enabled.

RoutingManager::updateEeTechRouteSetting only ORs NFA_TECHNOLOGY_MASK_F when
lf_protocol != 0, then ANDs with OFFHOST_LISTEN_TECH_MASK. On NX809J the eSE
(0x86) reports techF=0, so NFC_F_PASSIVE_LISTEN_MODE never starts.

Offsets are for Evolution X 17 apex com.android.nfcservices (BuildId
37ab93199ca893f1b2741d20388a24b9). Re-check after an NFC apex update.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

PATCHES = (
    (0x1634CC, bytes.fromhex("08018a1a"), bytes.fromhex("e8030a2a")),
    (0x1634DC, bytes.fromhex("3c01080a"), bytes.fromhex("fc03082a")),
)


def patch(src: Path, dst: Path) -> None:
    data = bytearray(src.read_bytes())
    for off, old, new in PATCHES:
        got = bytes(data[off : off + 4])
        if got == new:
            continue
        if got != old:
            raise SystemExit(
                f"unexpected bytes at 0x{off:x}: {got.hex()} (want {old.hex()} or {new.hex()})"
            )
        data[off : off + 4] = new
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)
    print(f"wrote {dst} ({len(data)} bytes)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("src", type=Path)
    ap.add_argument("-o", "--output", type=Path, default=Path("jni/libnfc_nci_jni.so"))
    args = ap.parse_args()
    patch(args.src, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
