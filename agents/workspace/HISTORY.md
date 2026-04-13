# Cycle History — Forex Bot Automation

Энэ файл дараалсан цикл бүрийн товчлолыг агуулна. `run_agents.py` цикл бүр дуусмагц автоматаар append хийнэ.

Format:

```
## Cycle N — YYYY-MM-DD HH:MM
- EA: FractalTBM_EA.mq5
- Changes: [Research agent requirement товч]
- Compile: ok | errors=X warnings=Y
- Backtest: XAUUSD M5, N months
- Result:
  - Overall win%: XX.X%
  - FRACTAL: TP/SL/BE = A/B/C, Win%: XX%
  - TBM: TP/SL/BE = A/B/C, Win%: XX% (disabled)
  - COMBINED: ...
  - Profit Factor: XX, Max DD: XX%
- Verdict: [target хангасан / ойртсон / ухарсан]
- Commit: <git sha>
```

---

<!-- CYCLES BELOW -->
