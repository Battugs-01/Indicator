# Цикл 1 — Шаардлага (Fractal сайжруулалт)

**Симбол / TF:** XAUUSD M5
**Baseline (2026-04-13):** 126 trade / 25.4% WR / PF 1.16 / Net +$3 / DD 5%
**Target:** нийт ≥42% WR, сар бүр ≥38% WR (6m backtest)
**Focus:** Зөвхөн Fractal sub-strategy (TBM унтраасан хэвээр)

---

## 1. Асуудлын диагноз

**Baseline grid харуулж байна:** бүх filter хослол (pure, session, vix, all-on) яг ижил 126/25.4% гаргасан → `.set`-ээр override ажиллахгүй. Тиймээс бүх дүрмийг **EA source-ын `input` default**-оор өөрчилнө.

Код дээр олдсон гол дутагдлууд (`FractalTBM_EA.mq5`):

1. **SL/TP хатуу тогтмол:** `InpSL_Pips=1000`, `InpTP_Pips=3000` (RR 1:3). Breakeven WR = 25% — одоогийн 25.4% бараг ирмэгтэй. Ганц нэг SL WR-г хэмнэлтгүй болгоно.
2. **Entry grade хэт сул:** `CheckEntry` (мөр 1087–1109) `grade=4` (зөвхөн CHOCH, "Pot") 1р болон 3р загварт зөвшөөрдөг. 2р загварт л `grade>2`-ийг хасдаг.
3. **1р загвар (Degi inner fractal) fires too often:** `f_inner_state` 0→5 алхамууд (мөр 779–856) зөвхөн 3+ range бар + body > ATR*0.5 шаардаж байна. M5 XAUUSD дээр noise-ийг шүүхгүй.
4. **3р загвар (waves>3)** — олон долгионтой PB нь чанаргүй. 2р л 1.5 RR reward/risk-д багтана.
5. **PB zone buffer хэт гэгээлэг:** `f_disp_zone_hi + atr_val*0.5` (мөр 762, 768). Zone-д жинхэнэ хүрэхгүй entry давж гарч байна.
6. **Session filter хэт өргөн:** 07–12 ба 13–17 UTC (мөр 993) — 10 цаг, low-liquidity цагийг агуулна.
7. **HTF alignment шаардлагагүй:** `htf_trend=0`-тэй ("тодорхойгүй") үед ч grade=4 гарч entry нээдэг.
8. **Candle confirmation заавал биш:** `candle_confirmed` зөвхөн grade=1/2-д шаардлагатай, grade 3–4-д унтардаг.
9. **Displacement валидаци сул:** `disp_range >= zone_range*1.5` + bars 2–10 (мөр 588). 1.5x ATR body (`InpDispMult=1.5`) M5 дээр хангалттай тод биш.
10. **Өдрийн trade хязгаар байхгүй** — 126/120 арилжааны өдөр = өдөрт дундаж 1 arilzhaa, гэвч кластер үед 4-5 гарна.

---

## 2. Засах зүйлс (EA source default-уудыг өөрчлөх)

### 2.1 Entry quality — grade гарцыг хатууруулах

- **Бүх загварт Grade ≤ 2 шаардах** (A.1 эсвэл A зэрэглэл). `CheckEntry` (мөр 1104–1106) дотор:
  - `grade_ok = (grade >= 1 && grade <= 2);` — загвар төрлөөс үл хамаарна.
- **Шалтгаан:** 25.4% WR дээрх trade-ийн дийлэнх нь grade 3/4 ("B", "Pot"). Эдгээрт liquidity sweep эсвэл candle confirm байхгүй.
- **Үр дүн:** trade тоо ~126 → 40–60 болно.

### 2.2 Зөвхөн 2р загвар идэвхжүүлэх

- **1р загвар (Degi inner fractal) унтраах:** `has_inner`-ийг entry шийдэлд үл тооцох, эсвэл `f_inner_state`-ийг бүхэлд нь bypass хийж `cur_pat = (f_pb_waves <= 3 ? 2 : 3);`
- **3р загвар (waves > 3) унтраах:** мөр 1065-д `cur_pat == 2` биш тохиолдолд skip.
- **Шалтгаан:** baseline log-д 1р загварын inner state машин M5 XAUUSD дээр noise-д шатаж, PB-г огт таних завгүй loss нээдэг. 2р загвар (1–3 wave PB → CHOCH) нь PDF Fractal_OT.pdf-ийн "Type B" загвартай хамгийн ойр.

### 2.3 HTF alignment заавал шаардах

- `CheckEntry` дотор: `if(htf_trend == 0) return;` — "тодорхойгүй" трэнд үед entry хориглох.
- `entry_bull`-ыг `(htf_trend == 1)`, `entry_bear`-ыг `(htf_trend == -1)` үед л зөвшөөрөх.
- **Шалтгаан:** 1H HH/HL trend-тэй тулалдахаа больсноор loss цуваа багасна.

### 2.4 Candle confirmation заавал (grade-ээс үл хамаарна)

- `entry_bull = entry_trigger_bull && candle_confirmed && ...` (мөр 1108).
- Одоо candle нь грейд тооцоололд л оролцдог, харин final gate шалгалтад үгүй.
- **Шалтгаан:** Engulfing / InsideBarBreak / CandleDisplacement аль нэг нь биелэхгүй CHOCH нь fakeout байх өндөр магадлалтай.

### 2.5 PB zone buffer чангаруулах

- `ProcessFractal` мөр 762, 768:
  - `f_disp_zone_hi + atr_val*0.5` → `f_disp_zone_hi + atr_val*0.15`
  - `f_disp_zone_lo - atr_val*0.5` → `f_disp_zone_lo - atr_val*0.15`
- **Шалтгаан:** Zone-ийн жинхэнэ дотор хүрсэн үед л "reached" тооцно. Одоогийн `0.5` buffer нь zone-оос 50% ATR зайтай entry-г хүчингүй нэвтрүүлдэг.

### 2.6 Displacement чангаруулах

- `InpDispMult`: **1.5 → 2.0** (мөр 26). Зөвхөн 2.0×ATR-аас том body-тай displacement л тооцно.
- `disp_range >= zone_range * 1.5` → `>= zone_range * 2.0` (мөр 588, 629).
- Bars хязгаар: `2 <= bars_used <= 10` → `2 <= bars_used <= 6` — хурдан displacement л хүчинтэй.
- **Шалтгаан:** PDF Fractal.pdf: "шилжүүлэгч" бол *хурдан, шийдэмгий* хөдөлгөөн. 3+ бар сунах нь structural impulse биш.

### 2.7 Cooldown + өдрийн limit

- `InpCooldown`: **20 → 30** bar (150 минут).
- Шинэ дотоод тоолуур нэмэх: `cnt_today_entries`, өдөрт **хамгийн ихдээ 3 Fractal entry** зөвшөөрнө. OnTick дээр `MqlDateTime` ашиглан өдөр солигдохоос шалгана.
- **Шалтгаан:** one-bar noise дараалан 3+ entry нээхийг хаана.

### 2.8 Session filter шахах

- `in_session = (hour >= 8 && hour <= 11) || (hour >= 13 && hour <= 16);` (мөр 993).
- London core (8–11 UTC) + NY core (13–16 UTC), overlap бага, news өмнөх халамцууг хасна.
- **Шалтгаан:** 7 UTC болон 17 UTC зах зээл тогтворгүй, 12 UTC лунч завсарлага.

### 2.9 SL/TP — RR-г бууруулж WR-д зай гаргах

- `InpSL_Pips`: **1000 → 800** ($0.80 зай).
- `InpTP_Pips`: **3000 → 1200** (RR 1:1.5 болгоно).
- `InpBE_Pips`: **1500 → 600** (ашиг 50%-д хүрмэгц BE шилжүүлнэ).
- **Шалтгаан:** RR 1:3 breakeven = 25% WR. RR 1:1.5-д breakeven = 40% WR — бидний 42% target-тай яг тааралдана. Target-г math-ийн хувьд боломжтой болгоно. Fixed pip хэвээр, зөвхөн харьцааг өөрчилж байна (measure-based TP дараагийн циклд).

### 2.10 Max spread чангаруулах

- `InpMaxSpread`: 40 → 25 pip. News / low-liq spread spike дээр entry нээгдэхгүй.

---

## 3. Хэрэгжүүлэх файлууд/мөрүүд

| # | Файл | Мөр | Өөрчлөлт |
|---|---|---|---|
| 1 | FractalTBM_EA.mq5 | 16 | `InpSL_Pips = 800` |
| 2 | FractalTBM_EA.mq5 | 17 | `InpTP_Pips = 1200` |
| 3 | FractalTBM_EA.mq5 | 18 | `InpBE_Pips = 600` |
| 4 | FractalTBM_EA.mq5 | 20 | `InpMaxSpread = 25` |
| 5 | FractalTBM_EA.mq5 | 26 | `InpDispMult = 2.0` |
| 6 | FractalTBM_EA.mq5 | 29 | `InpCooldown = 30` |
| 7 | FractalTBM_EA.mq5 | 588, 629 | `zone_range * 2.0` + `bars_used <= 6` |
| 8 | FractalTBM_EA.mq5 | 762, 768 | buffer `atr_val * 0.15` |
| 9 | FractalTBM_EA.mq5 | 993 | `(hour >= 8 && hour <= 11) \|\| (hour >= 13 && hour <= 16)` |
| 10 | FractalTBM_EA.mq5 | 1062 | `if(!f_pb_active \|\| cur_pat != 2) return;` (2р загвар л зөвшөөрнө) — тодруулбал Fractal блок бүхэлд нь 2р загвараар хаалттай |
| 11 | FractalTBM_EA.mq5 | 1065 | `cur_pat = 2;` (1р/3р таних тооцоо хэрэггүй) |
| 12 | FractalTBM_EA.mq5 | 1083 | `htf_aligned` шаардлагатай gate — `if(!htf_aligned) { grade = 0; }` |
| 13 | FractalTBM_EA.mq5 | 1104 | `grade_ok = (grade >= 1 && grade <= 2);` |
| 14 | FractalTBM_EA.mq5 | 1108-9 | entry_bull/bear-д `candle_confirmed` шаардах |
| 15 | FractalTBM_EA.mq5 | CheckEntry top | Өдрийн Fractal entry тоолуур (≤3/өдөр) |

---

## 4. Хүлээгдэж буй үр дүн

| Метрик | Baseline | Зорилго |
|---|---:|---:|
| Trade count (6m) | 126 | 40–70 |
| Нийт Win% | 25.4% | **≥42%** |
| Min month Win% | ~0% (sparse) | ≥38% |
| Profit Factor | 1.16 | ≥1.5 |
| Max DD | 5% | ≤6% |
| RR | 1:3 | 1:1.5 |

Үндэслэл: RR 1:1.5 дээр breakeven = 40% WR. Одоогийн 25.4%-ийн доторх grade=1/2 subset-ийг хотлоор хадгалж (code-д тэдгээрийн distribution log байгаа) 45–55% WR хүрэх боломжтой — backtest log-оор нотлогдох шаардлагатай.

---

## 5. Анхааруулга (ХИЙХГҮЙ зүйлс)

- **TBM-г бүү хөндө.** `InpTBMEnable` дотоод default хэвээрээ үлдэнэ, гэхдээ `CheckEntry`-ийн TBM блок нь `!InpTBMEnable` үед буцдаг учраас Fractal-д нөлөөлөхгүй. Хэрэглэгч "TBM орхи" гэж тусгайлан хэлсэн.
- **SMC / CRT / Elliott нэмэхгүй.** Эдгээр нь 2-р тэргүүлэхэд бүртгэгдсэн, зөвхөн Fractal ≥42% хангаснаас хойш авч үзнэ.
- **`.set` файл шинэчлэхгүй.** MT5 Strategy Tester дээр файлын override ажиллахгүй нь батлагдсан. Зөвхөн `input` default өөрчилнө.
- **Money management (InpRiskPct=2.0, MaxLot=1.0)** нь хэвээр үлдэнэ.
- **1H HTF BOS логик** (мөр 1001-1032) нь тогтвортой — зөвхөн gate болгон ашиглана, логикийг бичихгүй.
- **Engulfing / InsideBarBreak функцууд** нь хэвээр үлдэнэ (PDF-ийн butesh candle pattern-тэй уялдсан).

---

## 6. Validation plan (Developer agent-д зориулсан)

1. Compile `FractalTBM_EA.mq5` → 0 error.
2. `scripts/mt5_backtest.py` —6 сарын full run (2025-10-01 → 2026-03-31).
3. `scripts/run_monthly.py` — сар бүрийн WR, PF, trade count гарц.
4. `results.md` шинэчлэх, `HISTORY.md` append.
5. Хэрэв нийт WR < 42% бол Grade filter (2.1), 2р-only (2.2), эсвэл displacement (2.6) хэрэгжсэн эсэхийг log-оор шалгах. Trade count < 20/6m болвол хэт чанддаг гэж буцаан уян хатан болгоно (cooldown 30→25, disp 2.0→1.8).

---

*Research agent — Cycle 1 бичив 2026-04-13*
