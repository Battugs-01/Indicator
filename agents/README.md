# Forex Bot Automation Agents

## 2 Agent систем: Судлаач + Хөгжүүлэгч

### Agent 1: Research (Судлаач)
- PDF стратеги судлах (TBM, Fractal, Degi, SMC)
- Нэмэлт стратеги судлах (Elliott Wave, CRT)
- Одоогийн кодыг стратегитай харьцуулах
- Backtest лог задлах → алдаа олох
- Стратеги бүрийг XAUUSD M5-д үнэлэх
- Шаардлага гаргах → `workspace/requirements.md`

### Agent 2: Developer (Хөгжүүлэгч)
- Шаардлага унших → код засах / шинэ EA бичих
- Python-р compile + backtest хийх
- Үр дүн бичих → `workspace/results.md`
- Win rate < зорилго бол → Судлаач руу буцна

### Стратегиуд:
| Стратеги | PDF | Төлөв |
|----------|-----|-------|
| Degi Fractal | degi.pdf | ✅ Хэрэгжсэн |
| TBM | TBM STRATEGY.pdf | 🔧 Сайжруулж байна |
| SMC | SMART_MONEY_CONCEPT.pdf | 📋 Судлах |
| 5AM CRT | 5AM_CRT.pdf | 📋 Судлах |
| 9AM CRT | 9AM_CRT.pdf | 📋 Судлах |
| Elliott Wave | - | 📋 Судлах |

### Ажиллуулах:
```bash
# TBM сайжруулах
python run_agents.py --target-winrate 40 --max-cycles 10

# Бүх стратегийг судлах + хэрэгжүүлэх
python run_agents.py --target-winrate 40 --max-cycles 20 --mode full
```
