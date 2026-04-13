"""
MT5 орчны туслах функцууд — terminal path detect, stop/start,
EA файл хуулах, XAUUSD history татах.

Windows Server 2022 + MT5 build 5000+ дээр туршсан.
Бүх I/O utf-8.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

os.environ.setdefault("PYTHONIOENCODING", "utf-8")

MT5_INSTALL = Path(r"C:\Program Files\MetaTrader 5")
TERMINAL_EXE = MT5_INSTALL / "terminal64.exe"
METAEDITOR_EXE = MT5_INSTALL / "MetaEditor64.exe"

REPO_ROOT = Path(__file__).resolve().parent.parent


def get_data_path() -> Path:
    """MT5 terminal-ийн data folder-г Python API-р олно."""
    import MetaTrader5 as mt5

    if not mt5.initialize():
        raise RuntimeError(f"MT5 initialize алдаа: {mt5.last_error()}")
    try:
        ti = mt5.terminal_info()
        if ti is None:
            raise RuntimeError("terminal_info() None буцаалаа")
        return Path(ti.data_path)
    finally:
        mt5.shutdown()


def experts_dir(data_path: Path) -> Path:
    return data_path / "MQL5" / "Experts"


def is_terminal_running() -> bool:
    out = subprocess.run(
        ["tasklist.exe", "/FI", "IMAGENAME eq terminal64.exe", "/NH"],
        capture_output=True, text=True,
    )
    return "terminal64.exe" in out.stdout


def stop_terminal(timeout: float = 30.0) -> None:
    """terminal64.exe процессийг зөөлөн, дараа нь хүчтэй зогсооно."""
    if not is_terminal_running():
        return
    subprocess.run(["taskkill.exe", "/IM", "terminal64.exe"], capture_output=True)
    deadline = time.time() + timeout
    while time.time() < deadline and is_terminal_running():
        time.sleep(0.5)
    if is_terminal_running():
        subprocess.run(["taskkill.exe", "/F", "/IM", "terminal64.exe"], capture_output=True)
        time.sleep(1.0)


def start_terminal(data_path: Optional[Path] = None) -> None:
    """Live terminal-г сэргээнэ (монитор зорилгоор)."""
    if is_terminal_running():
        return
    subprocess.Popen([str(TERMINAL_EXE)], close_fds=True)


def copy_ea(src: Path, data_path: Path) -> Path:
    """EA .mq5 файлыг MQL5/Experts/ руу хуулна. Буцаах нь зорилтот зам."""
    dst_dir = experts_dir(data_path)
    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / src.name
    shutil.copy2(src, dst)
    return dst


def ensure_symbol(symbol: str = "XAUUSD") -> bool:
    """Symbol-г Market Watch-д нэмж, history цуглуулна."""
    import MetaTrader5 as mt5

    if not mt5.initialize():
        raise RuntimeError(f"MT5 init алдаа: {mt5.last_error()}")
    try:
        if not mt5.symbol_select(symbol, True):
            print(f"symbol_select амжилтгүй: {mt5.last_error()}", file=sys.stderr)
            return False
        info = mt5.symbol_info(symbol)
        if info is None:
            print(f"{symbol} олдсонгүй", file=sys.stderr)
            return False
        # history татахыг өдөөх
        end = datetime.now()
        start = end - timedelta(days=200)
        rates = mt5.copy_rates_range(symbol, mt5.TIMEFRAME_M5, start, end)
        n = 0 if rates is None else len(rates)
        print(f"{symbol} bars татсан: {n}")
        return n > 0
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    dp = get_data_path()
    print(f"DATA_PATH = {dp}")
    print(f"EXPERTS   = {experts_dir(dp)}")
    print(f"RUNNING   = {is_terminal_running()}")
