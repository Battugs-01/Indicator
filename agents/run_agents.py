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
from datetime import datetime
from pathlib import Path

# Замууд
BASE_DIR = Path(__file__).parent.parent
WORKSPACE = BASE_DIR / "agents" / "workspace"
EA_FILE = BASE_DIR / "FractalTBM_EA.mq5"
RESEARCH_PROMPT = BASE_DIR / "agents" / "research_prompt.md"
DEVELOPER_PROMPT = BASE_DIR / "agents" / "developer_prompt.md"

def setup_workspace():
    """Workspace фолдер үүсгэх"""
    WORKSPACE.mkdir(exist_ok=True)
    print(f"Workspace: {WORKSPACE}")

def run_research_agent(cycle: int):
    """Судлаач Agent ажиллуулах"""
    print(f"\n{'='*60}")
    print(f"  СУДЛААЧ AGENT — Цикл {cycle}")
    print(f"{'='*60}")

    prompt = f"""
Чи Судлаач Agent. Цикл #{cycle}.

{RESEARCH_PROMPT.read_text()}

Одоогийн файлууд:
- EA: {EA_FILE}
- PDF-үүд: {BASE_DIR}/pdfs/*.pdf
- Өмнөх үр дүн: {WORKSPACE}/results.md (байвал)

`{WORKSPACE}/requirements.md` файл руу шаардлага бичээрэй.
Цикл дугаар: {cycle}
"""

    result = subprocess.run(
        ["claude", "--print", "-p", prompt],
        capture_output=True, text=True, cwd=str(BASE_DIR),
        timeout=300
    )

    if result.returncode != 0:
        print(f"Судлаач алдаа: {result.stderr}")
        return False

    print(result.stdout[-500:] if len(result.stdout) > 500 else result.stdout)
    return True

def run_developer_agent(cycle: int):
    """Хөгжүүлэгч Agent ажиллуулах"""
    print(f"\n{'='*60}")
    print(f"  ХӨГЖҮҮЛЭГЧ AGENT — Цикл {cycle}")
    print(f"{'='*60}")

    prompt = f"""
Чи Хөгжүүлэгч Agent. Цикл #{cycle}.

{DEVELOPER_PROMPT.read_text()}

Шаардлага: {WORKSPACE}/requirements.md
EA файл: {EA_FILE}

Шаардлагыг уншиж, код засаж, compile хийж, backtest ажиллуулаад
`{WORKSPACE}/results.md` руу үр дүнг бичээрэй.
"""

    result = subprocess.run(
        ["claude", "--print", "-p", prompt],
        capture_output=True, text=True, cwd=str(BASE_DIR),
        timeout=600
    )

    if result.returncode != 0:
        print(f"Хөгжүүлэгч алдаа: {result.stderr}")
        return False

    print(result.stdout[-500:] if len(result.stdout) > 500 else result.stdout)
    return True

def check_winrate():
    """Backtest үр дүнгээс win rate шалгах — сар бүрийг тусад нь"""
    results_file = WORKSPACE / "results.md"
    if not results_file.exists():
        return 0.0, []

    content = results_file.read_text()
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
        logs = json.loads(log_file.read_text())

    logs.append({
        "cycle": cycle,
        "timestamp": datetime.now().isoformat(),
        "winrate": winrate
    })

    log_file.write_text(json.dumps(logs, indent=2))

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
