//+------------------------------------------------------------------+
//|                                              VixScalp_EA.mq5     |
//|                              © Battugs - Vix Fix 1min Scalper    |
//|         Ногоон → Саарал болход BUY | Ёроол → SELL | RR 1:2       |
//|         SL = entry лааны доод/дээд цэг                           |
//+------------------------------------------------------------------+
#property copyright "Battugs"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- INPUTS
input group "=== Money Management ==="
input double   InpRiskPct     = 2.0;      // Эрсдэлийн хувь (%)
input double   InpRR          = 2.0;      // Risk:Reward (1:2)
input double   InpMaxLot      = 1.0;      // Хамгийн их lot
input int      InpMaxSpread   = 30;       // Хамгийн их спрэд (pip)
input int      InpMaxPositions = 3;       // Хамгийн их нээлттэй позиц
input int      InpMagic       = 20260413; // Magic Number

input group "=== Williams Vix Fix (1min) ==="
input int      InpVixPeriod   = 22;       // LookBack Period
input int      InpVixBBLen    = 20;       // Bollinger Band Length
input double   InpVixBBMult   = 2.0;      // BB Standard Deviation
input int      InpVixPctLB    = 50;       // Percentile Lookback
input double   InpVixPctHi    = 0.85;     // Percentile High (0.85)
input double   InpVixPctLo    = 1.01;     // Percentile Low (1.01)
input int      InpGreenBars   = 2;        // Хамгийн багадаа хэдэн ногоон бар байсан байх

input group "=== Шүүлтүүр ==="
input bool     InpSessionFilter = true;   // Session шүүлтүүр
input int      InpSLBuffer    = 30;       // SL нэмэлт зай (points) — лааны доод/дээдээс

//--- GLOBAL
CTrade trade;

// Тоолуур
int cnt_buy = 0, cnt_sell = 0;
int cnt_tp = 0, cnt_sl = 0;
double total_pnl = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   Print("═══ VIX SCALP BOT ═══");
   Print("  1min | Vix Fix ", InpVixPeriod, " ", InpVixBBLen, " ", InpVixBBMult, " ", InpVixPctLB, " ", InpVixPctHi, " ", InpVixPctLo);
   Print("  RR 1:", InpRR, " | Risk: ", InpRiskPct, "%");
   Print("  Green bars шаардлага: ", InpGreenBars, "+");
   Print("═════════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("═══ VIX SCALP ТАЙЛАН ═══");
   Print("  BUY: ", cnt_buy, " | SELL: ", cnt_sell, " | Нийт: ", cnt_buy + cnt_sell);
   Print("  TP: ", cnt_tp, " | SL: ", cnt_sl);
   int total = cnt_tp + cnt_sl;
   Print("  Win%: ", total > 0 ? IntegerToString((int)MathRound(cnt_tp * 100.0 / total)) + "%" : "-");
   Print("  PnL: $", NormalizeDouble(total_pnl, 2));
   Print("═════════════════════════");
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   ulong deal_ticket = trans.deal;
   if(deal_ticket == 0) return;
   if(!HistoryDealSelect(deal_ticket)) return;
   if(HistoryDealGetInteger(deal_ticket, DEAL_MAGIC) != InpMagic) return;
   if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;

   double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
   string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);

   if(StringFind(comment, "tp") >= 0 || profit > 0) cnt_tp++;
   else cnt_sl++;
   total_pnl += profit;

   string reason = profit > 0 ? "TP ✅" : "SL ❌";
   Print("══ ", reason, " | PnL: $", NormalizeDouble(profit, 2), " | Нийт: $", NormalizeDouble(total_pnl, 2));
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) return;

   // Зөвхөн шинэ 1min лаа дээр
   static datetime last_bar = 0;
   datetime cur_bar = iTime(_Symbol, PERIOD_M1, 0);
   if(cur_bar == last_bar) return;
   last_bar = cur_bar;

   // Спрэд шалгах
   double pip = GetPipSize();
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if((ask - bid) / pip > InpMaxSpread) return;

   // Session шүүлтүүр
   if(InpSessionFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      bool in_session = (hour >= 7 && hour <= 12) || (hour >= 13 && hour <= 17);
      if(!in_session) return;
   }

   // Позицын тоо шалгах
   if(CountPositions() >= InpMaxPositions) return;

   // ═══ VIX FIX ДОХИО ШАЛГАХ ═══

   // Одоогийн бар-уудын мэдээлэл
   bool cur_green = IsGreen(1);
   bool prev_green = IsGreen(2);
   double c1_close = iClose(_Symbol, PERIOD_M1, 1);
   double c1_open = iOpen(_Symbol, PERIOD_M1, 1);
   double c2_close = iClose(_Symbol, PERIOD_M1, 2);

   // ── BUY: ногоон байсан → саарал болсон → БУЦАЛТ баталгаажсан ──
   // Алхам 1: Өмнө нь ногоон бар байсан (ёроол болсон)
   // Алхам 2: Одоо саарал (паник дуусч байна)
   // Алхам 3: Эхний ӨСӨЖ буй лаа (close > prev close) = буцалт баталгаажсан
   if(!cur_green)  // Одоо саарал
   {
      // Өмнөх бар-уудад ногоон байсан эсэх
      int green_count = 0;
      for(int i = 2; i <= InpGreenBars + 10; i++)
      {
         if(IsGreen(i)) green_count++;
      }

      // Буцалт баталгаажсан: close > өмнөх close (үнэ өсөж эхэлсэн)
      bool reversal_confirmed = (c1_close > c2_close) && (c1_close > c1_open);

      if(green_count >= InpGreenBars && reversal_confirmed)
      {
         // SL = ногоон бар-уудын хамгийн доод цэг (ёроолын жинхэнэ low)
         double bottom_low = iLow(_Symbol, PERIOD_M1, 1);
         for(int i = 2; i <= InpGreenBars + 10; i++)
         {
            if(IsGreen(i))
            {
               double lo = iLow(_Symbol, PERIOD_M1, i);
               if(lo < bottom_low) bottom_low = lo;
            }
         }

         double entry = ask;
         double sl = bottom_low - InpSLBuffer * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         double sl_dist = entry - sl;
         if(sl_dist <= 0) return;

         // SL хэт том бол алгасах (1min scalp учир хязгаарлах)
         if(sl_dist > pip * 500) return;  // 500 pip-с их SL = алгасна

         double tp = entry + sl_dist * InpRR;

         double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
         sl = MathRound(sl / tick_size) * tick_size;
         tp = MathRound(tp / tick_size) * tick_size;

         double lot = CalcLot(sl_dist);
         if(lot <= 0) return;

         if(trade.Buy(lot, _Symbol, 0, sl, tp, "VIX_BUY"))
         {
            cnt_buy++;
            double fill = trade.ResultPrice();
            Print("🟢 VIX BUY #", cnt_buy,
                  " | Fill: ", fill, " | Lot: ", lot,
                  " | SL: ", sl, " (-", NormalizeDouble(sl_dist/pip, 0), "p)",
                  " | TP: ", tp, " (+", NormalizeDouble((tp-fill)/pip, 0), "p)",
                  " | Green bars: ", green_count,
                  " | Bottom: ", bottom_low);
         }
      }
   }

   // SELL ормооргүй — зөвхөн BUY
}

//+------------------------------------------------------------------+
// WVF тооцоолох (1min дээр)
//+------------------------------------------------------------------+
double CalcWVF(int shift)
{
   double highest_close = 0;
   for(int i = shift; i < shift + InpVixPeriod; i++)
   {
      double cl = iClose(_Symbol, PERIOD_M1, i);
      if(cl > highest_close) highest_close = cl;
   }
   if(highest_close <= 0) return 0;
   double low_val = iLow(_Symbol, PERIOD_M1, shift);
   return ((highest_close - low_val) / highest_close) * 100.0;
}

//+------------------------------------------------------------------+
// Ногоон бар эсэх (оригинал Pine Script-тэй яг ижил)
// col = wvf >= upperBand or wvf >= rangeHigh ? lime : gray
//+------------------------------------------------------------------+
bool IsGreen(int shift)
{
   double wvf = CalcWVF(shift);

   // Bollinger Band: upperBand = sma(wvf, bbl) + mult * stdev(wvf, bbl)
   double sum = 0;
   for(int i = shift; i < shift + InpVixBBLen; i++)
      sum += CalcWVF(i);
   double midLine = sum / InpVixBBLen;

   double sum_sq = 0;
   for(int i = shift; i < shift + InpVixBBLen; i++)
   {
      double diff = CalcWVF(i) - midLine;
      sum_sq += diff * diff;
   }
   double sDev = InpVixBBMult * MathSqrt(sum_sq / InpVixBBLen);
   double upperBand = midLine + sDev;

   // Percentile: rangeHigh = highest(wvf, lb) * ph
   double wvf_highest = 0;
   for(int i = shift; i < shift + InpVixPctLB; i++)
   {
      double w = CalcWVF(i);
      if(w > wvf_highest) wvf_highest = w;
   }
   double rangeHigh = wvf_highest * InpVixPctHi;

   return (wvf >= upperBand) || (wvf >= rangeHigh);
}

//+------------------------------------------------------------------+
// Bollinger midLine тооцоолох
//+------------------------------------------------------------------+
double CalcMidLine()
{
   double sum = 0;
   for(int i = 1; i <= InpVixBBLen; i++)
      sum += CalcWVF(i);
   return sum / InpVixBBLen;
}

//+------------------------------------------------------------------+
// Pip хэмжээ
//+------------------------------------------------------------------+
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(digits == 3) return 0.01;
   if(digits == 2) return 0.01;
   if(digits == 1) return 0.1;
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
// Lot тооцоолол — SL зайнаас хамааруулж
//+------------------------------------------------------------------+
double CalcLot(double sl_dist)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * InpRiskPct / 100.0;

   // tick_value ашиглан lot тооцоолох
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tick_size <= 0 || tick_value <= 0) return 0;

   double sl_ticks = sl_dist / tick_size;
   double lot = risk_money / (sl_ticks * tick_value);

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lot_step) * lot_step;
   if(lot < min_lot) lot = min_lot;
   if(lot > InpMaxLot) lot = InpMaxLot;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
// Нээлттэй позиц тоолох
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic)
         count++;
   }
   return count;
}
//+------------------------------------------------------------------+
