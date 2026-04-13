"""
MT5 Strategy Tester-г command-line-р автомат ажиллуулах.

Flow:
  1. get_data_path()  -> data folder
  2. ensure_symbol()  -> XAUUSD Market Watch + history
  3. stop_terminal()  -> live terminal зогсоох (багц 1 instance л болно)
  4. tester.ini бичих
  5. terminal64.exe /config:tester.ini /portable  -> ShutdownTerminal=1 тул өөрөө хаагдана
  6. parse_report.py (тусад нь дуудна)

Ашиглалт:
    python scripts/mt5_backtest.py --ea FractalTBM_EA \
        --symbol XAUUSD --tf M5 --months 6 \
        --report results/cycle_0.htm
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

os.environ.setdefault("PYTHONIOENCODING", "utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mt5_utils import (  # noqa: E402
    TERMINAL_EXE,
    ensure_symbol,
    experts_dir,
    get_data_path,
    is_terminal_running,
    stop_terminal,
)

REPO_ROOT = Path(__file__).resolve().parent.parent

TESTER_INI_TEMPLATE = """\
[Tester]
Expert={ea}
Symbol={symbol}
Period={period}
Optimization=0
Model=2
FromDate={from_date}
ToDate={to_date}
ForwardMode=0
Deposit=10000
Currency=USD
ProfitInPips=0
Leverage=100
ExecutionMode=0
Report={report}
ReplaceReport=1
ShutdownTerminal=1
Visual=0
"""


def write_tester_ini(
    data_path: Path,
    ea: str,
    symbol: str,
    period: str,
    months: int,
    report_name: str,
) -> Path:
    end = datetime.now()
    start = end - timedelta(days=months * 31)
    # Config хавтас
    cfg_dir = data_path / "config"
    cfg_dir.mkdir(parents=True, exist_ok=True)
    ini_path = cfg_dir / "tester_auto.ini"
    content = TESTER_INI_TEMPLATE.format(
        ea=ea,
        symbol=symbol,
        period=period,
        from_date=start.strftime("%Y.%m.%d"),
        to_date=end.strftime("%Y.%m.%d"),
        report=report_name,
    )
    ini_path.write_text(content, encoding="utf-16-le")
    # MT5 ini файл UTF-16-LE BOM хэрэгтэй гэж үздэг
    ini_path.write_bytes(b"\xff\xfe" + content.encode("utf-16-le"))
    return ini_path


def run_terminal_tester(ini_path: Path, timeout: float = 900.0) -> dict[str, Any]:
    """terminal64.exe-г tester config-тай дуудна. ShutdownTerminal=1 → өөрөө хаагдана."""
    cmd = [str(TERMINAL_EXE), "/portable", f"/config:{ini_path}"]
    start = time.time()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"tester timeout ({timeout}s)"}
    elapsed = time.time() - start
    return {
        "ok": True,
        "return_code": proc.returncode,
        "elapsed_sec": round(elapsed, 1),
        "stdout": proc.stdout[-2000:] if proc.stdout else "",
        "stderr": proc.stderr[-2000:] if proc.stderr else "",
    }


def locate_report(data_path: Path, report_name: str) -> Path | None:
    """Report-ыг data folder дотроос хайна."""
    candidates = [
        data_path / report_name,
        data_path / "MQL5" / "Files" / report_name,
        data_path / "Tester" / report_name,
        data_path / f"{report_name}.htm",
        data_path / f"{report_name}.html",
    ]
    for c in candidates:
        if c.exists():
            return c
    # Глобал хайлт (хамгийн шинэ .htm)
    files = list((data_path).rglob(f"{report_name}*"))
    files = [f for f in files if f.is_file() and f.suffix.lower() in (".htm", ".html", ".xml")]
    if files:
        files.sort(key=lambda f: f.stat().st_mtime, reverse=True)
        return files[0]
    return None


def locate_latest_log(data_path: Path, since_ts: float) -> Path | None:
    logs_dir = data_path / "Tester" / "logs"
    if not logs_dir.exists():
        logs_dir = data_path / "MQL5" / "Logs"
    if not logs_dir.exists():
        return None
    logs = [f for f in logs_dir.glob("*.log") if f.stat().st_mtime >= since_ts]
    if not logs:
        return None
    logs.sort(key=lambda f: f.stat().st_mtime, reverse=True)
    return logs[0]


def run_backtest(
    ea: str,
    symbol: str = "XAUUSD",
    period: str = "M5",
    months: int = 6,
    report_name: str = "backtest_report",
    restart_live: bool = False,
) -> dict[str, Any]:
    data_path = get_data_path()
    experts = experts_dir(data_path)
    ex5 = experts / f"{ea}.ex5"
    if not ex5.exists():
        return {"ok": False, "error": f".ex5 not found, compile first: {ex5}"}

    print(f"[backtest] symbol={symbol} tf={period} months={months}")
    print(f"[backtest] data_path={data_path}")

    if not ensure_symbol(symbol):
        return {"ok": False, "error": f"symbol_select failed for {symbol}"}

    ini_path = write_tester_ini(data_path, ea, symbol, period, months, report_name)
    print(f"[backtest] ini={ini_path}")

    print("[backtest] stopping live terminal...")
    stop_terminal()
    since = time.time()

    print("[backtest] running tester...")
    run_info = run_terminal_tester(ini_path)

    report_path = locate_report(data_path, report_name)
    log_path = locate_latest_log(data_path, since)

    result = {
        **run_info,
        "ea": ea,
        "symbol": symbol,
        "period": period,
        "months": months,
        "ini_path": str(ini_path),
        "report_path": str(report_path) if report_path else None,
        "log_path": str(log_path) if log_path else None,
    }

    if restart_live:
        from mt5_utils import start_terminal
        print("[backtest] restarting live terminal...")
        start_terminal()

    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ea", required=True, help="EA нэр (extension-гүй, e.g. FractalTBM_EA)")
    ap.add_argument("--symbol", default="XAUUSD")
    ap.add_argument("--tf", default="M5")
    ap.add_argument("--months", type=int, default=6)
    ap.add_argument("--report", default="backtest_report")
    ap.add_argument("--restart-live", action="store_true")
    args = ap.parse_args()

    result = run_backtest(
        ea=args.ea,
        symbol=args.symbol,
        period=args.tf,
        months=args.months,
        report_name=args.report,
        restart_live=args.restart_live,
    )
    print(json.dumps({k: v for k, v in result.items() if k not in ("stdout", "stderr")},
                     ensure_ascii=False, indent=2))
    return 0 if result.get("ok") and result.get("report_path") else 1


if __name__ == "__main__":
    sys.exit(main())
