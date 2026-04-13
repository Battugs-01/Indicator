"""
Forex Bot 2-Agent автомат сайжруулалт систем
Судлаач Agent → Шаардлага → Хөгжүүлэгч Agent → Backtest → Давтах

Ажиллуулах: python run_agents.py --target-winrate 40 --max-cycles 10
VPS дээр: MT5 + Python + Claude Code суулгасан байх шаардлагатай
"""

import subprocess
import sys
import os
import json
import argparse
from datetime import datetime, timedelta
from pathlib import Path

# Windows дээр Cyrillic-ийн cp1252 алдаа гаргахгүйн тулд
os.environ.setdefault("PYTHONIOENCODING", "utf-8")
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    except Exception:
        pass

# Замууд
BASE_DIR = Path(__file__).parent.parent
WORKSPACE = BASE_DIR / "agents" / "workspace"
EA_FILE = BASE_DIR / "FractalTBM_EA.mq5"
RESEARCH_PROMPT = BASE_DIR / "agents" / "research_prompt.md"
DEVELOPER_PROMPT = BASE_DIR / "agents" / "developer_prompt.md"

# Claude CLI-ийн зам (Windows дээр .cmd байж магадгүй)
CLAUDE_CMD = os.environ.get("CLAUDE_CMD", "claude")

# Budget guard — 5-цагийн rate limit window-д 65% хүрэхэд зогсоно
BUDGET_CAP_USD = float(os.environ.get("BUDGET_CAP_USD", "130"))  # $200 x 65%
BUDGET_FILE = None  # set in setup_workspace()

def _subprocess_env() -> dict:
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["PYTHONUTF8"] = "1"
    return env


def setup_workspace():
    """Workspace фолдер үүсгэх"""
    WORKSPACE.mkdir(parents=True, exist_ok=True)
    global BUDGET_FILE
    BUDGET_FILE = WORKSPACE / "budget.json"
    if not BUDGET_FILE.exists():
        BUDGET_FILE.write_text(
            json.dumps({"window_start": datetime.now().isoformat(), "total_usd": 0.0, "calls": 0}),
            encoding="utf-8",
        )
    print(f"Workspace: {WORKSPACE}")


def _load_budget() -> dict:
    if BUDGET_FILE and BUDGET_FILE.exists():
        return json.loads(BUDGET_FILE.read_text(encoding="utf-8"))
    return {"window_start": datetime.now().isoformat(), "total_usd": 0.0, "calls": 0}


def _save_budget(b: dict) -> None:
    if BUDGET_FILE:
        BUDGET_FILE.write_text(json.dumps(b, indent=2), encoding="utf-8")


def _budget_window_reset_if_old(b: dict) -> dict:
    """5-цагийн window хуучирсан бол тэглэнэ."""
    start = datetime.fromisoformat(b["window_start"])
    if datetime.now() - start > timedelta(hours=5):
        return {"window_start": datetime.now().isoformat(), "total_usd": 0.0, "calls": 0}
    return b


def _wait_for_budget_reset(b: dict) -> None:
    start = datetime.fromisoformat(b["window_start"])
    resume_at = start + timedelta(hours=5, minutes=5)
    wait_sec = max(0, (resume_at - datetime.now()).total_seconds())
    print(f"\n⏸ BUDGET CAP (${b['total_usd']:.2f} >= ${BUDGET_CAP_USD}) — зогсоно")
    print(f"   Дахин сэрэх: {resume_at.isoformat()} ({wait_sec/60:.0f} мин)")
    import time
    time.sleep(wait_sec)


def _check_and_track_usage(response_json: dict) -> None:
    """Claude CLI JSON response-оос total_cost_usd уншиж budget-д нэмнэ."""
    cost = response_json.get("total_cost_usd") or response_json.get("cost_usd") or 0.0
    if not cost:
        return
    b = _load_budget()
    b = _budget_window_reset_if_old(b)
    b["total_usd"] = round(b["total_usd"] + float(cost), 4)
    b["calls"] = b.get("calls", 0) + 1
    _save_budget(b)
    print(f"  💰 budget: ${b['total_usd']:.3f} / ${BUDGET_CAP_USD} ({b['calls']} calls)")
    if b["total_usd"] >= BUDGET_CAP_USD:
        _wait_for_budget_reset(b)
        # Window reset
        _save_budget({"window_start": datetime.now().isoformat(), "total_usd": 0.0, "calls": 0})

def run_research_agent(cycle: int):
    """Судлаач Agent ажиллуулах"""
    print(f"\n{'='*60}")
    print(f"  СУДЛААЧ AGENT — Цикл {cycle}")
    print(f"{'='*60}")

    prompt = f"""
Чи Судлаач Agent. Цикл #{cycle}.

{RESEARCH_PROMPT.read_text(encoding='utf-8')}

Одоогийн файлууд:
- EA: {EA_FILE}
- PDF-үүд: {BASE_DIR}/pdfs/*.pdf
- Өмнөх үр дүн: {WORKSPACE}/results.md (байвал)

`{WORKSPACE}/requirements.md` файл руу шаардлага бичээрэй.
Цикл дугаар: {cycle}
"""

    result = subprocess.run(
        [CLAUDE_CMD, "--print", "--permission-mode", "bypassPermissions",
         "--output-format", "json"],
        input=prompt,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        cwd=str(BASE_DIR), timeout=1200, env=_subprocess_env(), shell=(os.name == "nt"),
    )
    try:
        response_json = json.loads(result.stdout) if result.stdout else {}
        _check_and_track_usage(response_json)
        if isinstance(response_json, dict) and response_json.get("result"):
            print(response_json["result"][-500:])
    except Exception:
        pass

    if result.returncode != 0:
        print(f"Судлаач алдаа: {result.stderr[-500:]}")
        return False
    return True

def run_developer_agent(cycle: int):
    """Хөгжүүлэгч Agent ажиллуулах"""
    print(f"\n{'='*60}")
    print(f"  ХӨГЖҮҮЛЭГЧ AGENT — Цикл {cycle}")
    print(f"{'='*60}")

    prompt = f"""
Чи Хөгжүүлэгч Agent. Цикл #{cycle}.

{DEVELOPER_PROMPT.read_text(encoding='utf-8')}

Шаардлага: {WORKSPACE}/requirements.md
EA файл: {EA_FILE}

Шаардлагыг уншиж, код засаж, compile хийж, backtest ажиллуулаад
`{WORKSPACE}/results.md` руу үр дүнг бичээрэй.
"""

    result = subprocess.run(
        [CLAUDE_CMD, "--print", "--permission-mode", "bypassPermissions",
         "--output-format", "json"],
        input=prompt,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        cwd=str(BASE_DIR), timeout=1800, env=_subprocess_env(), shell=(os.name == "nt"),
    )
    try:
        response_json = json.loads(result.stdout) if result.stdout else {}
        _check_and_track_usage(response_json)
        if isinstance(response_json, dict) and response_json.get("result"):
            print(response_json["result"][-500:])
    except Exception:
        pass

    if result.returncode != 0:
        print(f"Хөгжүүлэгч алдаа: {result.stderr[-500:]}")
        return False
    return True

def check_winrate():
    """Backtest үр дүнгээс win rate шалгах — сар бүрийг тусад нь"""
    results_file = WORKSPACE / "results.md"
    if not results_file.exists():
        return 0.0, []

    content = results_file.read_text(encoding='utf-8')
    import re

    # Нийт win rate
    matches = re.findall(r'Win%:\s*(\d+)%', content)
    overall = float(matches[-1]) if matches else 0.0

    # Сар бүрийн win rate (хэрэв байвал)
    monthly = re.findall(r'(\d{4}\.\d{2}).*?Win%:\s*(\d+)%', content)
    monthly_rates = [(m[0], float(m[1])) for m in monthly]

    return overall, monthly_rates

def save_cycle_log(cycle: int, winrate: float):
    """Цикл бүрийн лог хадгалах"""
    log_file = WORKSPACE / "cycle_log.json"
    logs = []
    if log_file.exists():
        logs = json.loads(log_file.read_text(encoding='utf-8'))

    logs.append({
        "cycle": cycle,
        "timestamp": datetime.now().isoformat(),
        "winrate": winrate
    })

    log_file.write_text(json.dumps(logs, indent=2), encoding='utf-8')

def main():
    parser = argparse.ArgumentParser(description="Forex Bot 2-Agent систем")
    parser.add_argument("--target-winrate", type=float, default=42.0,
                       help="Зорилго win rate (%%)")
    parser.add_argument("--min-winrate", type=float, default=38.0,
                       help="Дор хаяж win rate (%%) — БҮХ сарт заавал хангагдах ёстой")
    parser.add_argument("--max-cycles", type=int, default=20,
                       help="Хамгийн их давталт")
    parser.add_argument("--start-cycle", type=int, default=1,
                       help="Эхлэх цикл")
    parser.add_argument("--test-months", type=int, default=6,
                       help="Хэдэн сарын backtest хийх")
    parser.add_argument("--mode", choices=["tbm", "full"], default="full",
                       help="tbm=зөвхөн TBM засах, full=бүх стратеги судлах")
    args = parser.parse_args()

    setup_workspace()

    print(f"""
╔══════════════════════════════════════════════════════╗
║  FOREX BOT АВТОМАТ САЙЖРУУЛАЛТ                      ║
║  Зорилго: win rate >= {args.target_winrate}%                          ║
║  Дор хаяж: бүх сарт >= {args.min_winrate}%                        ║
║  Хамгийн их: {args.max_cycles} цикл | Горим: {args.mode}                  ║
║  Backtest: сүүлийн {args.test_months} сар, сар бүрийг тусад нь       ║
╚══════════════════════════════════════════════════════╝
    """)

    for cycle in range(args.start_cycle, args.start_cycle + args.max_cycles):
        print(f"\n{'#'*60}")
        print(f"#  ЦИКЛ {cycle}/{args.start_cycle + args.max_cycles - 1}")
        print(f"{'#'*60}")

        # 1. Судлаач
        if not run_research_agent(cycle):
            print("Судлаач алдаа → зогссон")
            break

        # 2. Хөгжүүлэгч
        if not run_developer_agent(cycle):
            print("Хөгжүүлэгч алдаа → зогссон")
            break

        # 3. Win rate шалгах — нийт + сар бүр
        winrate, monthly = check_winrate()
        save_cycle_log(cycle, winrate)

        print(f"\n  Цикл {cycle} үр дүн:")
        print(f"  Нийт Win Rate: {winrate}%")

        if monthly:
            all_above_min = True
            for month, rate in monthly:
                status = "✅" if rate >= args.min_winrate else "❌"
                print(f"    {month}: {rate}% {status}")
                if rate < args.min_winrate:
                    all_above_min = False

            if winrate >= args.target_winrate and all_above_min:
                print(f"\n  ЗОРИЛГО ХАНГАГДЛАА!")
                print(f"  Нийт: {winrate}% >= {args.target_winrate}%")
                print(f"  Бүх сар: >= {args.min_winrate}% ✅")
                break
            elif not all_above_min:
                print(f"\n  Зарим сарт {args.min_winrate}%-с доогуур → дахин засна...")
            else:
                print(f"\n  Нийт {winrate}% < {args.target_winrate}% → дахин засна...")
        else:
            if winrate >= args.target_winrate:
                print(f"\n  ЗОРИЛГО ХАНГАГДЛАА! {winrate}% >= {args.target_winrate}%")
                break
            print(f"  {winrate}% < {args.target_winrate}% → дараагийн цикл...")

    print(f"\n{'='*60}")
    print("  ДУУСЛАА")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()
