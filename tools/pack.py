#!/usr/bin/env python3
"""Zip module contents for KernelSU (module.prop at zip root, no .git)."""
from __future__ import annotations

import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKIP_DIR = {".git", "__pycache__"}
SKIP_FILE_SUFFIX = {".zip", ".pyc"}


def main() -> None:
    prop = (ROOT / "module.prop").read_text(encoding="utf-8")
    version = "1.0"
    for line in prop.splitlines():
        if line.startswith("version="):
            version = line.split("=", 1)[1].strip()
    out = ROOT / f"nx809j_felica-{version}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for path in sorted(ROOT.rglob("*")):
            if not path.is_file():
                continue
            rel = path.relative_to(ROOT)
            if any(p in SKIP_DIR for p in rel.parts):
                continue
            if path.suffix in SKIP_FILE_SUFFIX:
                continue
            if path.name == ".gitignore":
                continue
            zf.write(path, rel.as_posix())
            print(rel.as_posix())
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
