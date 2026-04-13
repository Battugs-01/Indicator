"""
MT5 Strategy Tester report + Journal log-оос үр дүнг гаргах.

Хоёр эх сурвалжаас уншина:
  1. Tester report (.htm / .xml) — нийт trade, PF, DD, win rate
  2. Tester journal log — FractalTBM.mq5-ын Print() дуудалтууд:
       "FRACTAL:  TP:X | SL:Y | BE:Z | Win%:N%"
       "TBM:      TP:X | SL:Y | BE:Z | Win%:N%"
       "COMBINED: TP:X | SL:Y | BE:Z | Win%:N%"

Буцаах: JSON + markdown (`results.md` format)
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

os.environ.setdefault("PYTHONIOENCODING", "utf-8")

REPO_ROOT = Path(__file__).resolve().parent.parent


def _read_text_multi(path: Path) -> str:
    if not path.exists():
        return ""
    raw = path.read_bytes()
    for enc in ("utf-16-le", "utf-16", "utf-8-sig", "utf-8", "cp1251"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace")


# ─── Tester HTML report parse ───────────────────────────────────────────
class _ReportHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.cells: list[str] = []
        self._buf: list[str] = []
        self._in_td = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in ("td", "th"):
            self._in_td = True
            self._buf = []

    def handle_endtag(self, tag: str) -> None:
        if tag in ("td", "th"):
            self._in_td = False
            self.cells.append("".join(self._buf).strip())

    def handle_data(self, data: str) -> None:
        if self._in_td:
            self._buf.append(data)


_NUM_RE = re.compile(r"-?[\d,]+\.?\d*")


def _find_near(cells: list[str], labels: list[str]) -> str | None:
    """Label-ын дараах ойролцоо cell-ээс тоон утга олно."""
    for i, c in enumerate(cells):
        for lb in labels:
            if lb.lower() in c.lower():
                # Дараагийн хоосон биш cell-ийг буцаана
                for j in range(i + 1, min(i + 4, len(cells))):
                    v = cells[j].strip()
                    if v and _NUM_RE.search(v):
                        return v
    return None


def parse_report_html(path: Path) -> dict[str, Any]:
    text = _read_text_multi(path)
    if not text:
        return {}
    p = _ReportHTMLParser()
    try:
        p.feed(text)
    except Exception as e:
        return {"parse_error": str(e)}

    cells = p.cells
    out: dict[str, Any] = {}

    def _num(s: str | None) -> float | None:
        if not s:
            return None
        m = _NUM_RE.search(s.replace(",", ""))
        if not m:
            return None
        try:
            return float(m.group())
        except ValueError:
            return None

    mapping = {
        "total_net_profit": ["Total Net Profit", "Нийт цэвэр ашиг"],
        "profit_factor":    ["Profit Factor", "Ашгийн хүчин зүйл"],
        "expected_payoff":  ["Expected Payoff", "Хүлээгдэж буй"],
        "max_drawdown_abs": ["Balance Drawdown Absolute", "Equity Drawdown Absolute"],
        "max_drawdown_pct": ["Maximal Drawdown", "Balance Drawdown Maximal"],
        "total_trades":     ["Total Trades", "Нийт арилжаа"],
        "profit_trades":    ["Profit Trades", "Ашигтай арилжаа"],
        "loss_trades":      ["Loss Trades", "Алдагдалтай арилжаа"],
        "win_rate_long":    ["Short Trades (won %)"],
        "short_trades":     ["Short Trades"],
        "long_trades":      ["Long Trades"],
        "gross_profit":     ["Gross Profit"],
        "gross_loss":       ["Gross Loss"],
    }
    for key, labels in mapping.items():
        val = _find_near(cells, labels)
        out[key] = _num(val) if val else None

    # Win rate нийтдээ
    if out.get("total_trades") and out.get("profit_trades") is not None:
        tt = out["total_trades"] or 0
        pt = out["profit_trades"] or 0
        out["win_rate_pct"] = round(100.0 * pt / tt, 2) if tt else None

    return out


# ─── Journal log parse — Print() counters ──────────────────────────────
_LINE_RE = re.compile(
    r"(FRACTAL|TBM|COMBINED)\s*:\s*TP\s*:\s*(\d+)\s*\|\s*SL\s*:\s*(\d+)\s*\|\s*BE\s*:\s*(\d+)"
    r"\s*\|\s*Win%\s*:\s*(\d+|N/A)",
    re.I,
)

_MONTH_BLOCK_RE = re.compile(r"(\d{4})\.(\d{2})")


def parse_journal_log(path: Path) -> dict[str, Any]:
    text = _read_text_multi(path)
    if not text:
        return {}

    strategies: dict[str, dict[str, Any]] = {}
    # Сүүлийн тохиолдлуудыг ашиглана (backtest эцэст хэвлэгддэг)
    for m in _LINE_RE.finditer(text):
        name = m.group(1).upper()
        tp = int(m.group(2))
        sl = int(m.group(3))
        be = int(m.group(4))
        win_raw = m.group(5)
        win = None if win_raw.upper() == "N/A" else int(win_raw)
        strategies[name] = {"tp": tp, "sl": sl, "be": be, "win_pct": win}

    return {"strategies": strategies, "log_size": len(text)}


def to_markdown(data: dict[str, Any], ea: str, cycle: int = 0) -> str:
    lines = [f"## Цикл {cycle} — Үр дүн ({ea})\n"]
    rep = data.get("report", {})
    strat = (data.get("journal", {}) or {}).get("strategies", {})

    lines.append("### Нийт үзүүлэлт (MT5 report)")
    lines.append("")
    lines.append(f"- Нийт арилжаа: {rep.get('total_trades')}")
    lines.append(f"- Ашигтай: {rep.get('profit_trades')} | Алдагдалтай: {rep.get('loss_trades')}")
    lines.append(f"- **Win rate: {rep.get('win_rate_pct')}%**")
    lines.append(f"- Profit Factor: {rep.get('profit_factor')}")
    lines.append(f"- Net Profit: {rep.get('total_net_profit')}")
    lines.append(f"- Max DD: {rep.get('max_drawdown_abs')} ({rep.get('max_drawdown_pct')}%)")
    lines.append("")

    if strat:
        lines.append("### Sub-strategy үр дүн (Journal log)")
        lines.append("")
        lines.append("| Стратеги | TP | SL | BE | Win% |")
        lines.append("|---|---:|---:|---:|---:|")
        for name in ("FRACTAL", "TBM", "COMBINED"):
            row = strat.get(name)
            if row:
                lines.append(f"| {name} | {row['tp']} | {row['sl']} | {row['be']} | {row['win_pct']}% |")
        lines.append("")

    return "\n".join(lines)


def parse_all(report_path: str | None, log_path: str | None, ea: str = "", cycle: int = 0) -> dict[str, Any]:
    result: dict[str, Any] = {
        "ea": ea,
        "cycle": cycle,
        "report_path": report_path,
        "log_path": log_path,
        "report": {},
        "journal": {},
    }
    if report_path:
        rp = Path(report_path)
        if rp.exists():
            result["report"] = parse_report_html(rp)
    if log_path:
        lp = Path(log_path)
        if lp.exists():
            result["journal"] = parse_journal_log(lp)
    result["markdown"] = to_markdown(result, ea=ea, cycle=cycle)
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", help="HTML report зам")
    ap.add_argument("--log", help="Journal log зам")
    ap.add_argument("--ea", default="")
    ap.add_argument("--cycle", type=int, default=0)
    ap.add_argument("--out-json")
    ap.add_argument("--out-md")
    args = ap.parse_args()

    data = parse_all(args.report, args.log, ea=args.ea, cycle=args.cycle)

    if args.out_json:
        Path(args.out_json).write_text(
            json.dumps({k: v for k, v in data.items() if k != "markdown"}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
    if args.out_md:
        Path(args.out_md).write_text(data["markdown"], encoding="utf-8")

    print(data["markdown"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
