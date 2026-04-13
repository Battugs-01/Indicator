"""
Сар бүрийн backtest дэлгэрэнгүй — 1 сар тус бүрээр ажиллуулж нэгтгэнэ.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

os.environ.setdefault("PYTHONIOENCODING", "utf-8")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from mt5_backtest import run_backtest  # noqa: E402
from mt5_backtest import write_tester_ini  # noqa: E402
from mt5_utils import TERMINAL_EXE, experts_dir, get_data_path, stop_terminal  # noqa: E402
from parse_report import parse_all  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "agents" / "workspace" / "cycles" / "baseline"


def month_range(months_back: int) -> list[tuple[datetime, datetime, str]]:
    """N сарын (from, to, label) жагсаалт гаргана. Хамгийн шинээс эхлэнэ."""
    out = []
    now = datetime.now().replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    for i in range(months_back):
        start_month = now - timedelta(days=30 * (i + 1))
        start_month = start_month.replace(day=1)
        end_month = (start_month + timedelta(days=31)).replace(day=1) - timedelta(days=1)
        label = start_month.strftime("%Y.%m")
        out.append((start_month, end_month, label))
    return list(reversed(out))


def run_one_month(ea: str, symbol: str, period: str, from_d: datetime, to_d: datetime, label: str) -> dict:
    data_path = get_data_path()
    report_name = f"monthly_{label.replace('.', '_')}"
    import subprocess

    # Custom ini with fixed date range
    from mt5_backtest import TESTER_INI_TEMPLATE
    content = TESTER_INI_TEMPLATE.format(
        ea=ea, symbol=symbol, period=period,
        from_date=from_d.strftime("%Y.%m.%d"),
        to_date=to_d.strftime("%Y.%m.%d"),
        report=report_name, expert_parameters="",
    )
    ini_path = data_path / "config" / f"tester_{label.replace('.', '_')}.ini"
    ini_path.parent.mkdir(parents=True, exist_ok=True)
    ini_path.write_bytes(b"\xff\xfe" + content.encode("utf-16-le"))

    stop_terminal()
    cmd = [str(TERMINAL_EXE), f"/config:{ini_path}"]
    subprocess.run(cmd, capture_output=True, timeout=600)

    report_path = data_path / f"{report_name}.htm"
    log_path = data_path / "Tester" / "logs" / f"{datetime.now():%Y%m%d}.log"

    parsed = parse_all(
        str(report_path) if report_path.exists() else None,
        str(log_path) if log_path.exists() else None,
        ea=ea, cycle=0,
    )
    rep = parsed.get("report", {}) or {}

    return {
        "month": label,
        "from": from_d.strftime("%Y-%m-%d"),
        "to": to_d.strftime("%Y-%m-%d"),
        "total_trades": rep.get("total_trades"),
        "profit_trades": rep.get("profit_trades"),
        "loss_trades": rep.get("loss_trades"),
        "win_rate_pct": rep.get("win_rate_pct"),
        "profit_factor": rep.get("profit_factor"),
        "net_profit": rep.get("total_net_profit"),
        "max_dd_pct": rep.get("max_drawdown_pct"),
        "report_path": str(report_path) if report_path.exists() else None,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ea", default="FractalTBM_EA")
    ap.add_argument("--symbol", default="XAUUSDm")
    ap.add_argument("--period", default="M5")
    ap.add_argument("--months", type=int, default=6)
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    for (f, t, lbl) in month_range(args.months):
        print(f"\n━━━ {lbl} ({f.strftime('%Y-%m-%d')} → {t.strftime('%Y-%m-%d')}) ━━━")
        try:
            row = run_one_month(args.ea, args.symbol, args.period, f, t, lbl)
            rows.append(row)
            print(f"  trades={row['total_trades']} win={row['win_rate_pct']}% "
                  f"pf={row['profit_factor']} net={row['net_profit']}")
        except Exception as e:
            print(f"  FAILED: {e}")
            rows.append({"month": lbl, "error": str(e)})

    # Нэгтгэх
    lines = [
        f"# Monthly Baseline — {args.ea} {args.symbol} {args.period}",
        f"\nRun: {datetime.now().isoformat()}",
        "\n| Month | Period | Trades | Wins | Losses | Win% | PF | Net | DD% |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        if "error" in r:
            lines.append(f"| {r['month']} | ERROR | — | — | — | — | — | {r['error']} | — |")
            continue
        lines.append(
            f"| {r['month']} | {r['from']}..{r['to']} | "
            f"{r['total_trades']} | {r['profit_trades']} | {r['loss_trades']} | "
            f"{r['win_rate_pct']}% | {r['profit_factor']} | {r['net_profit']} | {r['max_dd_pct']}% |"
        )

    md = "\n".join(lines) + "\n"
    (OUT_DIR / "monthly_baseline.md").write_text(md, encoding="utf-8")
    (OUT_DIR / "monthly_baseline.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n[saved] {OUT_DIR}/monthly_baseline.md")
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
