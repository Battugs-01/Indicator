"""
Baseline grid runner — хэд хэдэн config-ийг дараалан тест хийж,
нэгтгэсэн markdown тайлан үүсгэнэ.

Одоо ажиллах жишээ:
    python scripts/run_baselines.py --months 6 --symbol XAUUSDm --period M5

Бүрэлдэхүүн:
  1. Pure Fractal         (TBM=false, Vix=false, Session=false)
  2. + Session filter     (TBM=false, Vix=false, Session=true)
  3. + Vix Fix            (TBM=false, Vix=true,  Session=false)
  4. + Session + Vix      (TBM=false, Vix=true,  Session=true)
  5. Defaults (all on)    (TBM=true,  Vix=true,  Session=true)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime
from pathlib import Path

os.environ.setdefault("PYTHONIOENCODING", "utf-8")
sys.path.insert(0, str(Path(__file__).resolve().parent))

from mt5_backtest import run_backtest  # noqa: E402
from parse_report import parse_all  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = REPO_ROOT / "agents" / "workspace" / "cycles" / "baseline"


CONFIGS = {
    "1_pure_fractal":        {"InpTBMEnable": "false", "InpVixEnable": "false", "InpSessionFilter": "false"},
    "2_fractal_session":     {"InpTBMEnable": "false", "InpVixEnable": "false", "InpSessionFilter": "true"},
    "3_fractal_vix":         {"InpTBMEnable": "false", "InpVixEnable": "true",  "InpSessionFilter": "false"},
    "4_fractal_session_vix": {"InpTBMEnable": "false", "InpVixEnable": "true",  "InpSessionFilter": "true"},
    "5_all_on_defaults":     {"InpTBMEnable": "true",  "InpVixEnable": "true",  "InpSessionFilter": "true"},
}


def run_one(name: str, inputs: dict, symbol: str, period: str, months: int, ea: str) -> dict:
    print(f"\n━━━ {name} ━━━")
    result = run_backtest(
        ea=ea, symbol=symbol, period=period, months=months,
        report_name=f"baseline_{name}", set_inputs=inputs,
    )
    parsed = parse_all(result.get("report_path"), result.get("log_path"), ea=ea, cycle=0)
    rep = parsed.get("report", {}) or {}
    row = {
        "name": name,
        "inputs": inputs,
        "total_trades": rep.get("total_trades"),
        "win_rate_pct": rep.get("win_rate_pct"),
        "profit_factor": rep.get("profit_factor"),
        "total_net_profit": rep.get("total_net_profit"),
        "max_drawdown_abs": rep.get("max_drawdown_abs"),
        "max_drawdown_pct": rep.get("max_drawdown_pct"),
        "report_path": result.get("report_path"),
    }
    print(f"  trades={row['total_trades']} win={row['win_rate_pct']}% "
          f"pf={row['profit_factor']} net={row['total_net_profit']}")
    return row


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ea", default="FractalTBM_EA")
    ap.add_argument("--symbol", default="XAUUSDm")
    ap.add_argument("--period", default="M5")
    ap.add_argument("--months", type=int, default=6)
    args = ap.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    rows = []
    for name, inputs in CONFIGS.items():
        try:
            rows.append(run_one(name, inputs, args.symbol, args.period, args.months, args.ea))
        except Exception as e:
            print(f"  FAILED: {e}")
            rows.append({"name": name, "error": str(e)})

    # Нэгтгэсэн markdown
    lines = [
        f"# Baseline Grid — {args.ea} {args.symbol} {args.period} {args.months}m",
        f"\nRun timestamp: {datetime.now().isoformat()}",
        "",
        "| Config | Filters | Trades | Win% | PF | Net | DD% |",
        "|---|---|---:|---:|---:|---:|---:|",
    ]
    for r in rows:
        if "error" in r:
            lines.append(f"| {r['name']} | — | ERROR | — | — | {r['error']} | — |")
            continue
        filters = " / ".join(
            f"{k.replace('Inp','').replace('Enable','').replace('Filter','')}={v}"
            for k, v in (r["inputs"] or {}).items()
        )
        lines.append(
            f"| {r['name']} | {filters} | {r['total_trades']} | {r['win_rate_pct']}% | "
            f"{r['profit_factor']} | {r['total_net_profit']} | {r['max_drawdown_pct']}% |"
        )

    md = "\n".join(lines) + "\n"
    (OUT_DIR / "baseline_grid.md").write_text(md, encoding="utf-8")
    (OUT_DIR / "baseline_grid.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n[saved] {OUT_DIR}/baseline_grid.md")
    print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
