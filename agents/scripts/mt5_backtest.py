"""
MT5 Python API-р backtest ажиллуулах
VPS дээр MT5 суулгасан байх шаардлагатай

Ажиллуулах: python mt5_backtest.py --symbol XAUUSD --timeframe M5 --period 3m
"""

import MetaTrader5 as mt5
import argparse
import json
import sys
from datetime import datetime, timedelta
from pathlib import Path

WORKSPACE = Path(__file__).parent.parent / "workspace"

def run_backtest(symbol="XAUUSD", timeframe="M5", period_months=3):
    """MT5 backtest ажиллуулах"""

    if not mt5.initialize():
        print(f"MT5 холбогдож чадсангүй: {mt5.last_error()}")
        return None

    print(f"MT5 холбогдлоо: {mt5.terminal_info().name}")
    print(f"Symbol: {symbol} | TF: {timeframe} | Period: {period_months}m")

    # Backtest-ийн үр дүнг MT5 terminal-ийн лог файлаас унших
    # (MT5 Python API-р шууд strategy tester ажиллуулах боломжгүй,
    #  command line-р ажиллуулна)

    terminal_path = mt5.terminal_info().path
    print(f"Terminal: {terminal_path}")

    mt5.shutdown()

    # MT5 command line backtest
    # MetaTrader5.exe /config:backtest.ini
    import subprocess

    end_date = datetime.now()
    start_date = end_date - timedelta(days=period_months * 30)

    # Backtest config файл үүсгэх
    config = f"""[Tester]
Expert=FractalTBM_EA
Symbol={symbol}
Period={timeframe}
Deposit=1000
Leverage=100
Model=1
ExecutionMode=0
Optimization=0
FromDate={start_date.strftime('%Y.%m.%d')}
ToDate={end_date.strftime('%Y.%m.%d')}
Report=backtest_report
ReplaceReport=1
ShutdownTerminal=1
"""

    config_path = Path(terminal_path).parent / "MQL5" / "Profiles" / "Tester" / "backtest_auto.ini"
    config_path.write_text(config)
    print(f"Config: {config_path}")

    # MT5 ажиллуулах
    mt5_exe = Path(terminal_path).parent / "terminal64.exe"
    result = subprocess.run(
        [str(mt5_exe), f"/config:{config_path}"],
        capture_output=True, text=True, timeout=300
    )

    print(f"Backtest дууслаа (return code: {result.returncode})")

    # Лог файл унших
    log_dir = Path(terminal_path).parent / "MQL5" / "Logs"
    if log_dir.exists():
        # Хамгийн сүүлийн лог файл
        log_files = sorted(log_dir.glob("*.log"), key=lambda f: f.stat().st_mtime, reverse=True)
        if log_files:
            log_content = log_files[0].read_text(encoding='utf-16-le', errors='ignore')
            # Үр дүнг workspace руу хадгалах
            results_path = WORKSPACE / "backtest_raw.log"
            results_path.write_text(log_content)
            print(f"Лог хадгалагдлаа: {results_path}")
            return log_content

    return None

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--symbol", default="XAUUSD")
    parser.add_argument("--timeframe", default="M5")
    parser.add_argument("--period", default="3", type=int, help="Сар")
    args = parser.parse_args()

    run_backtest(args.symbol, args.timeframe, args.period)
