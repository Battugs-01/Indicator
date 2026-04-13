# Цикл 1 — Үр дүн

## Хийсэн засварууд

1. **FractalTBM_EA.mq5:26** — `InpDispMult` 1.8 (эхлээд 2.0 оролдсон, trade=0 болж relax). Шалтгаан: req 2.6.
2. **FractalTBM_EA.mq5:29** — `InpCooldown` 25 (эхлээд 30 оролдсон). Шалтгаан: req 2.7.
3. **FractalTBM_EA.mq5:590,631** — `disp_range >= zone_range * 1.8`, `bars_used <= 8` (эхлээд 2.0 / 6 оролдсон). Шалтгаан: req 2.6.
4. **FractalTBM_EA.mq5:1080** — Fractal блокыг зөвхөн 2р загвар (`f_pb_waves <= 3`) болгож, 1р (inner fractal) ба 3р (waves>3) унтраасан. Шалтгаан: req 2.2.
5. **FractalTBM_EA.mq5:~1098** — HTF alignment заавал (`if(htf_trend == 0 || !htf_aligned) return;`). Шалтгаан: req 2.3.
6. **FractalTBM_EA.mq5:~1122** — Grade gate чангаруулж `grade_ok = (grade >= 1 && grade <= 2)` — бүх загварт A.1/A зэрэглэл шаардана. Шалтгаан: req 2.1.
7. **FractalTBM_EA.mq5:~1125** — `entry_bull/bear` -д `candle_confirmed` заавал шаардсан. Шалтгаан: req 2.4.
8. **Байсан нь баталгаажсан:** `InpSL_Pips=800`, `InpTP_Pips=1200`, `InpBE_Pips=600`, `InpMaxSpread=25`, session 8–11/13–16 UTC, PB buffer `atr*0.15`, өдрийн 3 entry хязгаар — урьд нь зассан байсан.

## Compile
- OK
- Errors: 0
- Warnings: 0

## Backtest үр дүн (FractalTBM_EA, XAUUSDm M5, **1 сар — Шат 1**)

**Шат 1 АМЖИЛТГҮЙ — 0 entry**. Win% тооцохгүй (trade байхгүй).

Tester summary (sp 20260413.log):
- Fractal Bull disp: 4
- Fractal Bear disp: 4
- Displacement fail: 19
- PB зоно хүрсэн: 8
- **Entry BUY: 0 | SELL: 0**
- Net PnL: $0

Шат 2/3 руу ОРООГҮЙ — Шат 1 дээр зогссон.

## Баруутгал
- Baseline (126 trade / 25.4%) -тай харьцуулах: **trade count 0-д унасан** — шүүлтүүр хэт хатуу.
- Зорилгод ойртов уу? **Үгүй** — хэмжих ч боломжгүй. 1 сарт 21 орчим trade хүлээсэн ч 0 гарлаа.

## Диагноз (яагаад 0 entry?)

8 PB зонд хүрсэн ч нэг ч entry нээгдэхгүй байв — дараах гурван шаардлагын аль нэг нь устгасан:
1. **HTF gate (`htf_trend==0 || !htf_aligned`)** — 1H HH/HL эсвэл LH/LL тодорхой үед л зөвшөөрнө; ranging 1H үед бүгдийг устгана.
2. **Grade ≤ 2** — grade=1/2 хүрэхийн тулд `liq_sweep` + (`candle_confirmed` эсвэл `vix_confirmed`) заавал байх ёстой. Тэдгээр нь M5 дээр нэг дор давхцах нь ховор.
3. **Candle confirmation заавал** — Engulfing/InsideBarBreak/CandleDisplacement нь CHOCH-ийн яг тэр бар дээр тохиолдох нь ховор.

Req 2.1, 2.3, 2.4 гурвыг нэг зэрэг хатуу хэрэгжүүлсэн нь давхар шүүлтүүр (compound filter) үүсгэсэн. Ганцхан нь (гол төлөв HTF + candle) үлдвэл 20–40 trade/6m хүрэх боломжтой.

## Дараагийн алхам (Research agent-д санал)

1. **HTF gate-г grade тооцоонд л оруулах, final gate биш болгох.** `if(htf_trend==0) return;` мөрийг устгаж, `grade=3 (B)` байхыг дахин зөвшөөрөх (htf_aligned үед).
2. **Candle confirmation-г grade 1/2-д л шаардах, grade 3-т заавал биш.** Одоогийн `entry_bull && candle_confirmed` final gate-г sofftyг grade-ээр хамруулах.
3. **Grade gate 1-3 болгох** (4=Pot хориглосон хэвээр үлдэнэ). Grade 3 = CHOCH + HTF aligned, reasonable trade-ийг буцааж нээнэ.
4. **Displacement буцааж сул болгох санал:** `InpDispMult=1.5`, `zone_range*1.5`, bars 2–10 — 1 сард 20+ disp авах ёстой.
5. **Log-оос харах:** 8 PB reach-ийн аль нь HTF aligned байсан, аль нь candle тохирсон бэ — debug print нэмэх.
6. **Alternative:** TBM-ийг бас унтраалгүй тест хийх эсэх — одоогоор FractalOnly учир Fractal engine сайжруулахад анхаарах.
