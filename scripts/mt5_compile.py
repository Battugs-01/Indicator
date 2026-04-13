"""
MetaEditor64.exe-р .mq5 compile хийх wrapper.

Ашиглалт:
    python scripts/mt5_compile.py FractalTBM_EA.mq5
    python scripts/mt5_compile.py --ea FractalTBM_EA --data-path <optional>

Буцаах:
    JSON: {ok, ea, ex5_path, errors: [...], warnings: [...], log: str}
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

os.environ.setdefault("PYTHONIOENCODING", "utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mt5_utils import METAEDITOR_EXE, copy_ea, experts_dir, get_data_path  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent


def _read_log(path: Path) -> str:
    """MetaEditor лог нь ихэнхдээ UTF-16-LE эсвэл UTF-8 BOM-той."""
    if not path.exists():
        return ""
    raw = path.read_bytes()
    for enc in ("utf-16-le", "utf-16", "utf-8-sig", "utf-8", "cp1251"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


_ERR_RE = re.compile(r"^(?P<file>.+?)\((?P<line>\d+),(?P<col>\d+)\)\s*:\s*error\s*(?P<msg>.*)$", re.I | re.M)
_WRN_RE = re.compile(r"^(?P<file>.+?)\((?P<line>\d+),(?P<col>\d+)\)\s*:\s*warning\s*(?P<msg>.*)$", re.I | re.M)


def compile_ea(ea_filename: str) -> dict[str, Any]:
    """EA .mq5-г Experts/ руу хуулж, compile хийж, үр дүнг буцаана."""
    src = REPO_ROOT / ea_filename
    if not src.exists():
        return {"ok": False, "error": f"source not found: {src}"}

    data_path = get_data_path()
    dst = copy_ea(src, data_path)

    # Ижил нэртэй .mqh/.ex5-г мөн хуулах (хэрэв олдвол)
    mqh_src = src.with_suffix(".mqh")
    if mqh_src.exists():
        copy_ea(mqh_src, data_path)

    log_path = dst.with_suffix(".log")
    if log_path.exists():
        log_path.unlink()

    cmd = [
        str(METAEDITOR_EXE),
        f"/compile:{dst}",
        f"/log:{log_path}",
        "/inc:" + str(data_path / "MQL5"),
    ]

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "compile timeout (180s)"}

    log_text = _read_log(log_path)
    errors = [m.groupdict() for m in _ERR_RE.finditer(log_text)]
    warnings = [m.groupdict() for m in _WRN_RE.finditer(log_text)]

    ex5 = dst.with_suffix(".ex5")
    ok = ex5.exists() and not errors

    return {
        "ok": ok,
        "ea": ea_filename,
        "ex5_path": str(ex5) if ex5.exists() else None,
        "return_code": proc.returncode,
        "errors": errors,
        "warnings": warnings,
        "log_path": str(log_path),
        "log": log_text,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ea", help="EA .mq5 файлын нэр (repo root-оос)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    result = compile_ea(args.ea)

    if args.quiet:
        print(json.dumps({k: v for k, v in result.items() if k != "log"}, ensure_ascii=False, indent=2))
    else:
        print(json.dumps(result, ensure_ascii=False, indent=2))

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
