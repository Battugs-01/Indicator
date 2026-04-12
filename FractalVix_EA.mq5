//+------------------------------------------------------------------+
//|                                             FractalVix_EA.mq5    |
//|                                  © Battugs - Fractal + Vix Fix   |
//|                          Зөвхөн XAUUSD 5min | SL:100 TP:300     |
//|                     Fractal entry + CM Williams Vix Fix шүүлтүүр |
//+------------------------------------------------------------------+
#property copyright "Battugs"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- INPUTS
input group "=== Money Management ==="
input double   InpRiskPct     = 2.0;      // Эрсдэлийн хувь (%) — дансны 2%
input int      InpSL_Pips     = 1000;     // Stop Loss (1000 pip = $1.00 зай = 0.02 lot-д $20)
input int      InpTP_Pips     = 3000;     // Take Profit (3000 pip = $3.00 зай = 0.02 lot-д $60) RR 1:3
input int      InpBE_Pips     = 1500;     // 1500 pip ашигтай болоход SL-г BE болгох
input double   InpMaxLot      = 1.0;      // Хамгийн их lot (аюулгүй хязгаар)
input int      InpMaxSpread   = 40;       // Хамгийн их спрэд (pip) — энэнээс дээш бол entry нээхгүй
input int      InpMaxPositions = 5;      // Хамгийн их нэгэн зэрэг нээлттэй позиц
input int      InpMagic       = 20260406; // Magic Number

input group "=== Fractal ==="
input int      InpATR_Len     = 14;       // ATR Length
input double   InpDispMult    = 1.5;      // Шилжүүлэгч ATR x
input int      InpLookback    = 20;       // Бүс lookback
input double   InpMaxRange    = 5.0;      // Бүс max range (ATR x)
input int      InpCooldown    = 20;       // Cooldown (bars)
input int      InpSwingLen    = 5;        // Swing Length

input group "=== Шүүлтүүр ==="
input bool     InpSessionFilter = true;   // Session шүүлтүүр (London+NY)

input group "=== Williams Vix Fix (15min) ==="
input bool     InpVixEnable   = true;    // Vix Fix шүүлтүүр идэвхтэй
input int      InpVixPeriod   = 22;      // LookBack Period Standard Deviation High
input int      InpVixBBLen    = 20;      // Bollinger Band Length
input double   InpVixBBMult   = 2.0;     // Bollinger Band Standard Deviation Up
input int      InpVixPctLB    = 50;      // Look Back Period Percentile High
input double   InpVixPctHi    = 0.85;    // Highest Percentile (0.85=85%)
input double   InpVixPctLo    = 1.01;    // Lowest Percentile (1.01=99%)
input int      InpVixRecent   = 3;       // Сүүлийн N бар-д дохио байсан бол хүчинтэй

//--- GLOBAL
CTrade trade;
int atr_handle;
double atr_buf[];

// Fractal state
int    f_track_state = 0;
double f_track_extreme = 0;
double f_track_zone_hi = 0;
double f_track_zone_lo = 0;
int    f_track_start = 0;
int    f_disp_dir = 0;
double f_disp_extreme = 0;
double f_disp_zone_lo = 0;
double f_disp_zone_hi = 0;
int    f_bars_since_disp = 0;
bool   f_pb_started = false;
int    f_active_pattern = 0;
int    f_pb_waves = 0;
int    f_pb_wave_dir = 0;
int    f_pb_start_bar = 0;
bool   f_pb_inner_ranging = false;
bool   f_pb_inner_disp = false;
int    f_prev_cd = 0;
int    f_last_signal_bar = 0;

// Дотоод Fractal state (1р загварт)
// 0=хайж байна, 1=range олдсон, 2=дотоод PB, 3=шилжүүлэгч, 4=дотоод PB2, 5=impulse дуусаж
int    f_inner_state = 0;
double f_inner_range_hi = 0;
double f_inner_range_lo = 0;
int    f_inner_range_bars = 0;

// PB zone + CHOCH tracking
bool   f_pb_reached_zone = false;
double f_pb_swing_hi = 0;
double f_pb_swing_lo = 99999;

// PB дотрын жинхэнэ swing tracking
double f_pb_last_swing_hi = 0;   // Сүүлийн fix swing high (CHOCH level)
double f_pb_last_swing_lo = 0;   // Сүүлийн fix swing low
double f_pb_running_hi = 0;      // Одоогийн leg-ийн running high
double f_pb_running_lo = 99999;  // Одоогийн leg-ийн running low
int    f_pb_leg_dir = 0;         // Одоогийн leg чиглэл (1=up, -1=down)
int    f_pb_leg_bars = 0;        // Одоогийн leg-д хэдэн бар болсон

// Swing arrays (Fractal-д ашиглагдана)
double sh_prices[];  int sh_bars[];   int sh_count = 0;
double sl_prices[];  int sl_bars[];   int sl_count = 0;
bool   new_ph_found = false;
bool   new_pl_found = false;

// Partial close tracking — ticket-р хянана

// Entry cooldown (race condition хамгаалалт)
datetime last_entry_time = 0;


// ─── Trade тоолуур ───
int cnt_fractal_buy = 0;
int cnt_fractal_sell = 0;
int cnt_fractal_disp_bull = 0;
int cnt_fractal_disp_bear = 0;
int cnt_fractal_disp_fail = 0;
int cnt_fractal_pb_start = 0;
int cnt_fractal_pb_expire = 0;

// ─── Загвар бүрийн TP/SL тоолуур ───
int pat1_entry = 0, pat1_tp = 0, pat1_sl = 0;
int pat2_entry = 0, pat2_tp = 0, pat2_sl = 0;
int pat3_entry = 0, pat3_tp = 0, pat3_sl = 0;
double pat1_pnl = 0, pat2_pnl = 0, pat3_pnl = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(50);  // 50 points slippage (gold-д хэвийн)
   trade.SetTypeFilling(ORDER_FILLING_IOC);  // IOC fill mode

   atr_handle = iATR(_Symbol, PERIOD_M5, InpATR_Len);
   if(atr_handle == INVALID_HANDLE) return INIT_FAILED;


   ArrayResize(sh_prices, 30); ArrayResize(sh_bars, 30);
   ArrayResize(sl_prices, 30); ArrayResize(sl_bars, 30);

   // Брокерийн мэдээлэл лог
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   long stops_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   ENUM_ACCOUNT_MARGIN_MODE acc_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);

   Print("═══ BROKER INFO ═══");
   Print("  Symbol: ", _Symbol, " | Digits: ", digits, " | Point: ", point);
   Print("  TickSize: ", tick_size, " | TickValue: $", tick_value);
   Print("  PipSize: ", GetPipSize(), " | SL dist: ", InpSL_Pips * GetPipSize(), " | TP dist: ", InpTP_Pips * GetPipSize());
   Print("  StopsLevel: ", stops_level, " pts | FreezeLevel: ", freeze_level, " pts");
   Print("  Account mode: ", acc_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ? "HEDGING" : "NETTING");
   Print("  Risk: $", GetRiskMoney(), " | SL:", InpSL_Pips, " TP:", InpTP_Pips, " | RR 1:3");
   Print("  Шүүлтүүр: HTF Balance(1H) + Session(", InpSessionFilter ? "ON" : "OFF", ") + PB Zone + CHOCH/Shift + Trailing");
   Print("═══════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);

   Print("═══════════════════════════════════════════");
   Print("         НИЙТ ТАЙЛАН (SUMMARY)            ");
   Print("═══════════════════════════════════════════");
   Print("── FRACTAL ──");
   Print("  Шилжүүлэгч Bull: ", cnt_fractal_disp_bull, " | Bear: ", cnt_fractal_disp_bear, " | Fail: ", cnt_fractal_disp_fail);
   Print("  PB эхэлсэн: ", cnt_fractal_pb_start, " | Хугацаа дууссан: ", cnt_fractal_pb_expire);
   Print("  Entry BUY: ", cnt_fractal_buy, " | SELL: ", cnt_fractal_sell, " | Нийт: ", cnt_fractal_buy + cnt_fractal_sell);
   Print("── ЗАГВАР БҮРИЙН ҮР ДҮН ──");
   Print("  1р загвар: ", pat1_entry, " entry | TP: ", pat1_tp, " | SL: ", pat1_sl,
         " | Win%: ", pat1_entry > 0 ? IntegerToString((int)MathRound(pat1_tp * 100.0 / pat1_entry)) + "%" : "-",
         " | PnL: $", NormalizeDouble(pat1_pnl, 2));
   Print("  2р загвар: ", pat2_entry, " entry | TP: ", pat2_tp, " | SL: ", pat2_sl,
         " | Win%: ", pat2_entry > 0 ? IntegerToString((int)MathRound(pat2_tp * 100.0 / pat2_entry)) + "%" : "-",
         " | PnL: $", NormalizeDouble(pat2_pnl, 2));
   Print("  3р загвар: ", pat3_entry, " entry | TP: ", pat3_tp, " | SL: ", pat3_sl,
         " | Win%: ", pat3_entry > 0 ? IntegerToString((int)MathRound(pat3_tp * 100.0 / pat3_entry)) + "%" : "-",
         " | PnL: $", NormalizeDouble(pat3_pnl, 2));
   Print("── НИЙТ ──");
   int total = cnt_fractal_buy + cnt_fractal_sell;
   Print("  Бүх entry: ", total);
   Print("  Нийт PnL: $", NormalizeDouble(pat1_pnl + pat2_pnl + pat3_pnl, 2));
   Print("═══════════════════════════════════════════");
}

//+------------------------------------------------------------------+
// Trade хаагдах бүрд дэлгэрэнгүй лог бичих
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong deal_ticket = trans.deal;
   if(deal_ticket == 0) return;

   if(!HistoryDealSelect(deal_ticket)) return;

   long deal_magic = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
   if(deal_magic != InpMagic) return;

   long deal_entry = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
   string deal_comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
   double deal_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
   double deal_volume = HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
   double deal_profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
   double deal_commission = HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
   double deal_swap = HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
   long deal_type = HistoryDealGetInteger(deal_ticket, DEAL_TYPE);

   string type_str = deal_type == DEAL_TYPE_BUY ? "BUY" : "SELL";

   if(deal_entry == DEAL_ENTRY_IN)
   {
      // Оролт нээгдлээ
      Print("══ OPEN ══ ", type_str, " | Price: ", deal_price,
            " | Volume: ", deal_volume, " | Comment: ", deal_comment);
   }
   else if(deal_entry == DEAL_ENTRY_OUT)
   {
      // Оролт хаагдлаа — SL/TP/Manual ялгах
      double pip = GetPipSize();
      double total_pnl = deal_profit + deal_commission + deal_swap;

      // Position-н нээсэн үнийг олох
      ulong pos_id = HistoryDealGetInteger(deal_ticket, DEAL_POSITION_ID);
      double open_price = 0;
      string open_comment = "";
      HistorySelectByPosition(pos_id);
      for(int k = 0; k < HistoryDealsTotal(); k++)
      {
         ulong od = HistoryDealGetTicket(k);
         if(HistoryDealGetInteger(od, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            open_price = HistoryDealGetDouble(od, DEAL_PRICE);
            open_comment = HistoryDealGetString(od, DEAL_COMMENT);
            break;
         }
      }
      HistorySelect(0, TimeCurrent());

      double move_pips = 0;
      if(deal_type == DEAL_TYPE_SELL)  // BUY позиц хаагдаж байна (SELL deal)
         move_pips = (deal_price - open_price) / pip;
      else  // SELL позиц хаагдаж байна (BUY deal)
         move_pips = (open_price - deal_price) / pip;

      string reason = "???";
      if(StringFind(deal_comment, "tp") >= 0) reason = "TP HIT ✅";
      else if(StringFind(deal_comment, "sl") >= 0) reason = "SL HIT ❌";
      else reason = "OTHER: " + deal_comment;

      Print("══ CLOSE ══ ", reason, " | Open: ", open_price, " → Close: ", deal_price,
            " | Move: ", NormalizeDouble(move_pips, 1), " pips",
            " | PnL: $", NormalizeDouble(total_pnl, 2),
            " | Volume: ", deal_volume,
            " | Type: ", open_comment);


      // Загвар бүрийн TP/SL тоолох (comment + profit аль алинаар)
      bool is_tp = (StringFind(deal_comment, "tp") >= 0) || (total_pnl > 0);
      bool is_sl = (StringFind(deal_comment, "sl") >= 0) && (total_pnl <= 0);

      if(StringFind(open_comment, "_1р_") >= 0 || StringFind(open_comment, "_1p_") >= 0)
      {
         pat1_entry++;
         if(is_tp) pat1_tp++; else if(is_sl) pat1_sl++;
         pat1_pnl += total_pnl;
      }
      else if(StringFind(open_comment, "_2р_") >= 0 || StringFind(open_comment, "_2p_") >= 0)
      {
         pat2_entry++;
         if(is_tp) pat2_tp++; else if(is_sl) pat2_sl++;
         pat2_pnl += total_pnl;
      }
      else if(StringFind(open_comment, "_3р_") >= 0 || StringFind(open_comment, "_3p_") >= 0)
      {
         pat3_entry++;
         if(is_tp) pat3_tp++; else if(is_sl) pat3_sl++;
         pat3_pnl += total_pnl;
      }
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Зөвхөн XAUUSD
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) return;

   // 1500 pip ашигтай болоход SL → BE
   CheckBreakEven();

   // Entry шалгах (tick бүрд — 61.8-д хүрсэн мөчид шууд entry)
   double atr_val_rt = GetATR();
   if(atr_val_rt > 0) CheckEntry(atr_val_rt);

   // Fractal тооцоолол: зөвхөн шинэ 5min лаа дээр
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, PERIOD_M5, 0);
   if(current_bar_time == last_bar_time) return;
   last_bar_time = current_bar_time;

   double atr_val = GetATR();
   if(atr_val <= 0) return;

   UpdateSwings();
   ProcessFractal(atr_val);
}

//+------------------------------------------------------------------+
double GetATR()
{
   double buf[1];
   if(CopyBuffer(atr_handle, 0, 1, 1, buf) <= 0) return 0;
   return buf[0];
}

//+------------------------------------------------------------------+
// Lot size автомат тооцоолол
// Balance * Risk% = Risk$
// Risk$ / (SL pips * pip value) = Lot
// Жишээ: $1000 * 2% = $20 / (100 pips * $0.1/pip) = 0.02 lot
//+------------------------------------------------------------------+
double GetRiskMoney()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   return balance * InpRiskPct / 100.0;
   // $1000 * 2% = $20
   // $2000 * 2% = $40
   // $5000 * 2% = $100 — compound growth
}

// Алтны pip хэмжээг брокерийн digit-с автомат тооцох
double GetPipSize()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   // XAUUSD: 2 digit (4675.50) → pip = 0.01
   //         1 digit (4675.5)  → pip = 0.1
   //         3 digit (4675.501) → pip = 0.01 (3дахь нь sub-pip)
   if(digits == 3) return 0.01;   // 3 digit: pip = 0.01
   if(digits == 2) return 0.01;   // 2 digit: pip = 0.01
   if(digits == 1) return 0.1;    // 1 digit: pip = 0.1
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT); // fallback
}

double CalcLotSize()
{
   // Энгийн lot тооцоолол:
   // $1000-$1399 → 0.02  (SL $20, TP $60)
   // $1400-$1799 → 0.03  (SL $30, TP $90)
   // $400 нэмэгдэх тутамд +0.01
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double base_lot = 0.02;
   double extra = 0;
   if(balance > 1000.0)
      extra = MathFloor((balance - 1000.0) / 400.0) * 0.01;

   double lot = base_lot + extra;

   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lot_step) * lot_step;
   if(lot < min_lot) lot = min_lot;
   if(lot > InpMaxLot) lot = InpMaxLot;

   Print("💰 Lot | Balance: $", NormalizeDouble(balance, 2), " | Lot: ", NormalizeDouble(lot, 2));
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
double GetOpen(int shift)  { return iOpen(_Symbol, PERIOD_M5, shift); }
double GetHigh(int shift)  { return iHigh(_Symbol, PERIOD_M5, shift); }
double GetLow(int shift)   { return iLow(_Symbol, PERIOD_M5, shift); }
double GetClose(int shift) { return iClose(_Symbol, PERIOD_M5, shift); }

//+------------------------------------------------------------------+
void UpdateSwings()
{
   new_ph_found = false;
   new_pl_found = false;

   // Pivot High: bar[InpSwingLen] нь 2*InpSwingLen+1 бар-н хамгийн өндөр үү
   double pivot_h = GetHigh(InpSwingLen);
   bool is_ph = true;
   for(int j = 0; j < InpSwingLen * 2 + 1; j++)
   {
      if(j == InpSwingLen) continue;
      if(GetHigh(j) > pivot_h) { is_ph = false; break; }
   }
   if(is_ph && pivot_h > 0)
   {
      bool dup = false;
      if(sh_count > 0 && MathAbs(sh_prices[0] - pivot_h) < SymbolInfoDouble(_Symbol, SYMBOL_POINT)) dup = true;
      if(!dup)
      {
         if(sh_count < 30) sh_count++;
         for(int k = sh_count - 1; k > 0; k--) { sh_prices[k] = sh_prices[k-1]; sh_bars[k] = sh_bars[k-1]; }
         sh_prices[0] = pivot_h;
         sh_bars[0] = iBarShift(_Symbol, PERIOD_M5, iTime(_Symbol, PERIOD_M5, InpSwingLen));
         new_ph_found = true;
      }
   }

   // Pivot Low
   double pivot_l = GetLow(InpSwingLen);
   bool is_pl = true;
   for(int j = 0; j < InpSwingLen * 2 + 1; j++)
   {
      if(j == InpSwingLen) continue;
      if(GetLow(j) < pivot_l) { is_pl = false; break; }
   }
   if(is_pl && pivot_l > 0)
   {
      bool dup = false;
      if(sl_count > 0 && MathAbs(sl_prices[0] - pivot_l) < SymbolInfoDouble(_Symbol, SYMBOL_POINT)) dup = true;
      if(!dup)
      {
         if(sl_count < 30) sl_count++;
         for(int k = sl_count - 1; k > 0; k--) { sl_prices[k] = sl_prices[k-1]; sl_bars[k] = sl_bars[k-1]; }
         sl_prices[0] = pivot_l;
         sl_bars[0] = iBarShift(_Symbol, PERIOD_M5, iTime(_Symbol, PERIOD_M5, InpSwingLen));
         new_pl_found = true;
      }
   }
}

//+------------------------------------------------------------------+
void ProcessFractal(double atr_val)
{
   int cur_bar = iBars(_Symbol, PERIOD_M5);
   double body_size = MathAbs(GetClose(1) - GetOpen(1));
   bool is_big_bull = body_size > atr_val * InpDispMult && GetClose(1) > GetOpen(1);
   bool is_big_bear = body_size > atr_val * InpDispMult && GetClose(1) < GetOpen(1);

   // Бүс шалгах — Pine Script-тэй ижил: bar 2-с эхлэх (bar 1 = displacement candle)
   double prev_hi = GetHigh(2);
   double prev_lo = GetLow(2);
   for(int i = 3; i <= InpLookback + 1; i++)
   {
      double h = GetHigh(i);
      double l = GetLow(i);
      if(h > prev_hi) prev_hi = h;
      if(l < prev_lo) prev_lo = l;
   }
   double prev_range = prev_hi - prev_lo;
   bool was_ranging = prev_range < atr_val * InpMaxRange;

   if(f_disp_dir != 0) f_bars_since_disp++;

   bool in_cooldown = (cur_bar - f_last_signal_bar) < InpCooldown;


   // Tracking эхлүүлэх
   if(f_track_state == 0 && !in_cooldown)
   {
      // Том лаа олдсон ч бусад нөхцөл хангагдаагүй бол лог бичих
      if(is_big_bull || is_big_bear)
      {
         bool broke_hi = GetClose(1) > prev_hi;
         bool broke_lo = GetClose(1) < prev_lo;
         Print("📊 FRACTAL: Том лаа! | ", is_big_bull ? "BULL" : "BEAR",
               " | body: ", NormalizeDouble(body_size, 2),
               " | ranging: ", was_ranging, " (range: ", NormalizeDouble(prev_range, 2), " max: ", NormalizeDouble(atr_val * InpMaxRange, 2), ")",
               " | broke_hi: ", broke_hi, " broke_lo: ", broke_lo);
      }

      if(is_big_bull && was_ranging && GetClose(1) > prev_hi)
      {
         f_track_state = 1;
         f_track_extreme = GetHigh(1);
         f_track_zone_hi = prev_hi;
         f_track_zone_lo = prev_lo;
         f_track_start = cur_bar;
         Print("📊 FRACTAL: Bull tracking эхэллээ! | Zone: ", prev_lo, "-", prev_hi);
      }
      if(is_big_bear && was_ranging && GetClose(1) < prev_lo)
      {
         f_track_state = -1;
         f_track_extreme = GetLow(1);
         f_track_zone_hi = prev_hi;
         f_track_zone_lo = prev_lo;
         f_track_start = cur_bar;
         Print("📊 FRACTAL: Bear tracking эхэллээ! | Zone: ", prev_lo, "-", prev_hi);
      }
   }

   // Bull tracking
   if(f_track_state == 1)
   {
      if(GetHigh(1) > f_track_extreme) f_track_extreme = GetHigh(1);
      double body_lo = MathMin(GetOpen(1), GetClose(1));
      double prev_body_lo = MathMin(GetOpen(2), GetClose(2));
      if(GetClose(1) < GetOpen(1) && body_lo < prev_body_lo)
      {
         double zone_range = f_track_zone_hi - f_track_zone_lo;
         double disp_range = MathAbs(f_track_extreme - f_track_zone_lo);
         int bars_used = cur_bar - f_track_start;
         Print("📊 FRACTAL: Bull validate | disp_range: ", NormalizeDouble(disp_range, 2),
               " zone_range: ", NormalizeDouble(zone_range, 2),
               " bars: ", bars_used,
               " pass: ", (disp_range >= zone_range && bars_used <= 10));
         if(disp_range >= zone_range * 1.5 && bars_used >= 2 && bars_used <= 10)
         {
            f_disp_dir = 1;
            f_disp_extreme = f_track_extreme;
            f_disp_zone_lo = f_track_zone_lo;
            f_disp_zone_hi = f_track_zone_hi;
            f_bars_since_disp = 0;
            f_pb_started = false;
            f_active_pattern = 0;
            f_last_signal_bar = cur_bar;
            cnt_fractal_disp_bull++;
            Print("📊 FRACTAL: Bull шилжүүлэгч олдлоо ✅ #", cnt_fractal_disp_bull, " | Zone: ", f_disp_zone_lo, "-", f_disp_zone_hi,
                  " | Extreme: ", f_disp_extreme, " | Bars: ", bars_used);
         }
         else
         {
            cnt_fractal_disp_fail++;
            Print("📊 FRACTAL: Bull validate АМЖИЛТГҮЙ ❌ #", cnt_fractal_disp_fail, " | bars: ", bars_used);
            f_disp_dir = 0;
            f_pb_started = false;
            f_active_pattern = 0;
         }
         f_track_state = 0;
      }
   }

   // Bear tracking
   if(f_track_state == -1)
   {
      if(GetLow(1) < f_track_extreme) f_track_extreme = GetLow(1);
      double body_hi = MathMax(GetOpen(1), GetClose(1));
      double prev_body_hi = MathMax(GetOpen(2), GetClose(2));
      if(GetClose(1) > GetOpen(1) && body_hi > prev_body_hi)
      {
         double zone_range = f_track_zone_hi - f_track_zone_lo;
         double disp_range = MathAbs(f_track_extreme - f_track_zone_hi);
         int bars_used = cur_bar - f_track_start;
         Print("📊 FRACTAL: Bear validate | disp_range: ", NormalizeDouble(disp_range, 2),
               " zone_range: ", NormalizeDouble(zone_range, 2),
               " bars: ", bars_used,
               " pass: ", (disp_range >= zone_range && bars_used <= 10));
         if(disp_range >= zone_range * 1.5 && bars_used >= 2 && bars_used <= 10)
         {
            f_disp_dir = -1;
            f_disp_extreme = f_track_extreme;
            f_disp_zone_lo = f_track_zone_lo;
            f_disp_zone_hi = f_track_zone_hi;
            f_bars_since_disp = 0;
            f_pb_started = false;
            f_active_pattern = 0;
            f_last_signal_bar = cur_bar;
            cnt_fractal_disp_bear++;
            Print("📊 FRACTAL: Bear шилжүүлэгч олдлоо ✅ #", cnt_fractal_disp_bear, " | Zone: ", f_disp_zone_lo, "-", f_disp_zone_hi,
                  " | Extreme: ", f_disp_extreme, " | Bars: ", bars_used);
         }
         else
         {
            cnt_fractal_disp_fail++;
            Print("📊 FRACTAL: Bear validate АМЖИЛТГҮЙ ❌ #", cnt_fractal_disp_fail, " | bars: ", bars_used);
            f_disp_dir = 0;
            f_pb_started = false;
            f_active_pattern = 0;
         }
         f_track_state = 0;
      }
   }

   // PB tracking
   if(f_disp_dir != 0 && f_bars_since_disp > 0 && f_active_pattern == 0)
   {
      int cur_cd = GetClose(1) > GetOpen(1) ? 1 : -1;
      bool is_sig = body_size > atr_val * 0.3;

      if(f_disp_dir == 1)
      {
         if(!f_pb_started && GetClose(1) < GetOpen(1))
         {
            f_pb_started = true;
            f_pb_start_bar = cur_bar;
            f_pb_waves = 1;
            f_pb_wave_dir = -1;
            f_pb_inner_ranging = false;
            f_pb_inner_disp = false;
            f_inner_state = 0;
            f_inner_range_bars = 0;
            f_pb_reached_zone = false;
            f_pb_swing_hi = GetHigh(1);
            f_pb_swing_lo = GetLow(1);
            f_pb_last_swing_hi = 0;
            f_pb_last_swing_lo = 0;
            f_pb_running_hi = GetHigh(1);
            f_pb_running_lo = GetLow(1);
            f_pb_leg_dir = -1;  // Bull disp → PB доош эхэлнэ
            f_pb_leg_bars = 0;
            cnt_fractal_pb_start++;
            Print("📊 FRACTAL: Bull PB эхэллээ #", cnt_fractal_pb_start, " | bars_since_disp: ", f_bars_since_disp);
         }
         if(!f_pb_started && f_bars_since_disp > 10)
         {
            cnt_fractal_pb_expire++;
            f_disp_dir = 0;
         }
      }
      else if(f_disp_dir == -1)
      {
         if(!f_pb_started && GetClose(1) > GetOpen(1))
         {
            f_pb_started = true;
            f_pb_start_bar = cur_bar;
            f_pb_waves = 1;
            f_pb_wave_dir = 1;
            f_pb_inner_ranging = false;
            f_pb_inner_disp = false;
            f_inner_state = 0;
            f_inner_range_bars = 0;
            f_pb_reached_zone = false;
            f_pb_swing_hi = GetHigh(1);
            f_pb_swing_lo = GetLow(1);
            f_pb_last_swing_hi = 0;
            f_pb_last_swing_lo = 0;
            f_pb_running_hi = GetHigh(1);
            f_pb_running_lo = GetLow(1);
            f_pb_leg_dir = 1;  // Bear disp → PB дээш эхэлнэ
            f_pb_leg_bars = 0;
            cnt_fractal_pb_start++;
         }
         if(!f_pb_started && f_bars_since_disp > 10)
         {
            cnt_fractal_pb_expire++;
            Print("📊 FRACTAL: Bear шилжүүлэгч хугацаа дууслаа #", cnt_fractal_pb_expire);
            f_disp_dir = 0;
         }
      }

      if(f_pb_started && f_active_pattern == 0)
      {
         if(cur_cd != f_pb_wave_dir && f_pb_wave_dir != 0 && is_sig)
            f_pb_waves++;
         if(is_sig)
            f_pb_wave_dir = cur_cd;

         // ── PB zone check + жинхэнэ swing tracking ──
         f_pb_running_hi = MathMax(f_pb_running_hi, GetHigh(1));
         f_pb_running_lo = MathMin(f_pb_running_lo, GetLow(1));
         f_pb_leg_bars++;

         // PB max swing (хуучин — бүх PB-ийн max/min)
         if(GetHigh(1) > f_pb_swing_hi) f_pb_swing_hi = GetHigh(1);
         if(GetLow(1) < f_pb_swing_lo) f_pb_swing_lo = GetLow(1);

         // ── Leg чиглэл солигдсон уу? (2+ эсрэг лаа) ──
         if(is_sig && f_pb_leg_bars >= 2)
         {
            if(cur_cd == 1 && f_pb_leg_dir == -1)
            {
               // Доош → Дээш солигдлоо: доод цэг fix = swing low
               f_pb_last_swing_lo = f_pb_running_lo;
               f_pb_running_lo = GetLow(1);
               f_pb_leg_dir = 1;
               f_pb_leg_bars = 0;
            }
            else if(cur_cd == -1 && f_pb_leg_dir == 1)
            {
               // Дээш → Доош солигдлоо: дээд цэг fix = swing high
               f_pb_last_swing_hi = f_pb_running_hi;
               f_pb_running_hi = GetHigh(1);
               f_pb_leg_dir = -1;
               f_pb_leg_bars = 0;
            }
         }

         if(f_disp_dir == 1)
         {
            // Bull disp → PB доош → zone-ийн дээд хэсэгт хүрсэн үү?
            if(GetLow(1) <= f_disp_zone_hi + atr_val * 0.5)
               f_pb_reached_zone = true;
         }
         else if(f_disp_dir == -1)
         {
            // Bear disp → PB дээш → zone-ийн доод хэсэгт хүрсэн үү?
            if(GetHigh(1) >= f_disp_zone_lo - atr_val * 0.5)
               f_pb_reached_zone = true;
         }

         // ── Дотоод Fractal tracking (1р загварт) ──
         // Bull PB (доошоо) дотор:
         //   (1) range → (2) PB дээшээ → (3) шилжүүлэгч доошоо → (4) PB дээшээ → (5) impulse дээшээ
         // Bear PB (дээшээ) дотор: эсрэгээр
         int pb_bars_now = cur_bar - f_pb_start_bar;

         // Алхам 1: Range олох
         if(f_inner_state == 0 && pb_bars_now >= 4)
         {
            double local_hi = GetHigh(1);
            double local_lo = GetLow(1);
            for(int r = 2; r <= 5 && r >= 1; r++) { local_hi = MathMax(local_hi, GetHigh(r)); local_lo = MathMin(local_lo, GetLow(r)); }
            double local_range = local_hi - local_lo;
            if(local_range < atr_val * 2.0)
            {
               f_inner_state = 1;
               f_inner_range_hi = local_hi;
               f_inner_range_lo = local_lo;
               f_inner_range_bars = 0;
            }
         }

         // Range track
         if(f_inner_state == 1)
         {
            f_inner_range_bars++;
            f_inner_range_hi = MathMax(f_inner_range_hi, GetHigh(1));
            f_inner_range_lo = MathMin(f_inner_range_lo, GetLow(1));
         }

         if(f_disp_dir == 1)  // Bull шилжүүлэгч → PB доошоо
         {
            // Алхам 2: Дотоод PB (дээшээ буцалт)
            if(f_inner_state == 1 && f_inner_range_bars >= 3)
            {
               if(GetClose(1) > GetOpen(1) && is_sig)
                  f_inner_state = 2;
            }
            // Алхам 3: Шилжүүлэгч (доошоо) — range-н low эвдэх
            if(f_inner_state == 2)
            {
               if(GetClose(1) < GetOpen(1) && GetClose(1) < f_inner_range_lo && body_size > atr_val * 0.5)
                  f_inner_state = 3;
            }
            // Алхам 4: Дотоод PB (дээшээ буцалт)
            if(f_inner_state == 3)
            {
               if(GetClose(1) > GetOpen(1) && is_sig)
                  f_inner_state = 4;
            }
            // Алхам 5: Impulse дуусаж (дээшээ хүчтэй) → Degi entry хүлээнэ
            if(f_inner_state == 4)
            {
               if(GetClose(1) > GetOpen(1) && body_size > atr_val * 0.5)
                  f_inner_state = 5;
            }
         }
         else if(f_disp_dir == -1)  // Bear шилжүүлэгч → PB дээшээ
         {
            if(f_inner_state == 1 && f_inner_range_bars >= 3)
            {
               if(GetClose(1) < GetOpen(1) && is_sig)
                  f_inner_state = 2;
            }
            if(f_inner_state == 2)
            {
               if(GetClose(1) > GetOpen(1) && GetClose(1) > f_inner_range_hi && body_size > atr_val * 0.5)
                  f_inner_state = 3;
            }
            if(f_inner_state == 3)
            {
               if(GetClose(1) < GetOpen(1) && is_sig)
                  f_inner_state = 4;
            }
            if(f_inner_state == 4)
            {
               if(GetClose(1) < GetOpen(1) && body_size > atr_val * 0.5)
                  f_inner_state = 5;
            }
         }

         // inner state-г хуучин variable-д sync хийх
         f_pb_inner_ranging = f_inner_state >= 1;
         f_pb_inner_disp = f_inner_state >= 5;
      }

      f_prev_cd = cur_cd;
   }
}


//+------------------------------------------------------------------+
void CheckEntry(double atr_val)
{
   int cur_bar = iBars(_Symbol, PERIOD_M5);
   double pip = GetPipSize();
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double bid_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Спрэд шалгах
   double spread_pips = (ask_price - bid_price) / pip;
   if(spread_pips > InpMaxSpread)
      return;

   // ── Session шүүлтүүр: London (07-12 UTC) + NY (13-17 UTC) ──
   if(InpSessionFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      bool in_session = (hour >= 7 && hour <= 12) || (hour >= 13 && hour <= 17);
      if(!in_session) return;
   }

   // Race condition хамгаалалт
   if(TimeCurrent() - last_entry_time < 5)
      return;

   // ── HTF Balance: 1H BOS/Trend шалгах ──
   // 1H swing олж, BOS (body break) илрүүлэх
   int htf_trend = 0;       // 0=тодорхойгүй, 1=bull, -1=bear
   bool htf_finalize = false; // 1H BOS body-р баталгаажсан
   {
      // Сүүлийн 1H swing high/low олох
      double h1_swing_hi = 0, h1_swing_lo = 99999;
      double h1_prev_hi = 0, h1_prev_lo = 99999;
      for(int i = 1; i <= 20; i++)
      {
         double h = iHigh(_Symbol, PERIOD_H1, i);
         double l = iLow(_Symbol, PERIOD_H1, i);
         if(h > h1_swing_hi) h1_swing_hi = h;
         if(l < h1_swing_lo) h1_swing_lo = l;
      }
      // Өмнөх 1H swing (20-40 бар)
      for(int i = 21; i <= 40; i++)
      {
         double h = iHigh(_Symbol, PERIOD_H1, i);
         double l = iLow(_Symbol, PERIOD_H1, i);
         if(h > h1_prev_hi) h1_prev_hi = h;
         if(l < h1_prev_lo) h1_prev_lo = l;
      }
      // HH/HL = bull, LH/LL = bear
      if(h1_swing_hi > h1_prev_hi && h1_swing_lo > h1_prev_lo) htf_trend = 1;
      else if(h1_swing_hi < h1_prev_hi && h1_swing_lo < h1_prev_lo) htf_trend = -1;

      // BOS: сүүлийн 1H close нь өмнөх swing-г body-р эвдсэн
      double h1_close = iClose(_Symbol, PERIOD_H1, 1);
      if(h1_close > h1_prev_hi) htf_finalize = true;   // Bull BOS
      if(h1_close < h1_prev_lo) htf_finalize = true;   // Bear BOS
   }

   // ── Liquidity Sweep: PB zone дотор sweep → буцсан ──
   bool liq_sweep = false;
   if(f_disp_dir == 1 && f_pb_started)
   {
      // Bull disp → PB доош → zone-ийн доод хэсгийг sweep хийж буцсан
      if(f_pb_swing_lo <= f_disp_zone_lo && bid_price > f_disp_zone_lo)
         liq_sweep = true;
      // Zone-ийн дотор хүрсэн ч бас тооцно
      if(f_pb_swing_lo <= f_disp_zone_hi && bid_price > f_disp_zone_hi)
         liq_sweep = true;
   }
   if(f_disp_dir == -1 && f_pb_started)
   {
      // Bear disp → PB дээш → zone-ийн дээд хэсгийг sweep хийж буцсан
      if(f_pb_swing_hi >= f_disp_zone_hi && ask_price < f_disp_zone_hi)
         liq_sweep = true;
      if(f_pb_swing_hi >= f_disp_zone_lo && ask_price < f_disp_zone_lo)
         liq_sweep = true;
   }

   int open_count = CountOpenPositions();

   // Fractal PB идэвхитэй + zone-д хүрсэн эсэх
   bool f_pb_active = f_disp_dir != 0 && f_pb_started && f_active_pattern == 0 && f_pb_reached_zone;

   // ═══════════════════════════════════════════
   // FRACTAL ENTRY — CHOCH + Grade + Candle + Vix шүүлтүүр
   // ═══════════════════════════════════════════
   if(f_pb_active)
   {
      bool has_inner = f_pb_inner_ranging && f_pb_inner_disp;
      int cur_pat = has_inner ? 1 : (f_pb_waves <= 3 ? 2 : 3);

      // ── Entry trigger: CHOCH ──
      bool entry_trigger_bull = false;
      bool entry_trigger_bear = false;

      entry_trigger_bull = (f_disp_dir == 1 && f_pb_last_swing_hi > 0 && bid_price > f_pb_last_swing_hi);
      entry_trigger_bear = (f_disp_dir == -1 && f_pb_last_swing_lo > 0 && ask_price < f_pb_last_swing_lo);

      // ── Candle Pattern баталгаа (шинэ) ──
      bool f_candle_bull = IsEngulfing(1) || IsInsideBarBreak(1) || IsCandleDisplacement(1, atr_val);
      bool f_candle_bear = IsEngulfing(-1) || IsInsideBarBreak(-1) || IsCandleDisplacement(-1, atr_val);

      // ── Williams Vix Fix баталгаа (шинэ) ──
      bool f_vix_bull = IsVixFixSignal(1);
      bool f_vix_bear = IsVixFixSignal(-1);

      // ── Entry Grade тодорхойлох (сайжруулсан) ──
      bool htf_aligned = (f_disp_dir == 1 && htf_trend == 1) || (f_disp_dir == -1 && htf_trend == -1);
      bool candle_confirmed = (f_disp_dir == 1 && f_candle_bull) || (f_disp_dir == -1 && f_candle_bear);
      bool vix_confirmed = (f_disp_dir == 1 && f_vix_bull) || (f_disp_dir == -1 && f_vix_bear);

      int grade = 0;
      // A.1: CHOCH + Liq + HTF BOS + Candle + Vix (бүгд)
      if(liq_sweep && htf_finalize && candle_confirmed && vix_confirmed && (entry_trigger_bull || entry_trigger_bear))
         grade = 1;
      // A: CHOCH + Liq + HTF aligned + (Candle эсвэл Vix)
      else if(liq_sweep && htf_aligned && (candle_confirmed || vix_confirmed) && (entry_trigger_bull || entry_trigger_bear))
         grade = 2;
      // B: CHOCH + HTF aligned
      else if(htf_aligned && (entry_trigger_bull || entry_trigger_bear))
         grade = 3;
      // Pot: зөвхөн CHOCH (2р загварт зөвшөөрөхгүй)
      else if((entry_trigger_bull || entry_trigger_bear))
         grade = 4;

      string grade_name = grade == 1 ? "A.1" : grade == 2 ? "A" : grade == 3 ? "B" : grade == 4 ? "Pot" : "NONE";

      // ── 2р загварт Grade B+ шаардах (win rate 25% → сайжруулах) ──
      bool grade_ok = true;
      if(cur_pat == 2 && grade > 2)
         grade_ok = false;  // 2р загвар: заавал A.1 эсвэл A

      bool entry_bull = (entry_trigger_bull && grade >= 1 && grade <= 4 && grade_ok);
      bool entry_bear = (entry_trigger_bear && grade >= 1 && grade <= 4 && grade_ok);

      string pat_name = cur_pat == 1 ? "1р" : cur_pat == 2 ? "2р" : "3р";

      // Аль нэг чиглэлд FRACTAL нээлттэй бол шинээр нээхгүй (netting хамгаалалт)
      bool has_any_fractal = HasOpenPosition(POSITION_TYPE_BUY, "FRACTAL") || HasOpenPosition(POSITION_TYPE_SELL, "FRACTAL");

      // ── Лог: яагаад entry нээгдээгүй ──
      if((entry_trigger_bull || entry_trigger_bear) && !grade_ok)
      {
         Print("📊 FRACTAL: ", pat_name, " алгассан | Grade: ", grade_name, " (хангалтгүй)",
               " | Candle: ", candle_confirmed, " | Vix: ", vix_confirmed,
               " | Liq: ", liq_sweep, " | HTF: ", htf_aligned);
      }

      if(entry_bull && open_count < InpMaxPositions && !has_any_fractal)
      {
         double lot = CalcLotSize();
         double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(lot < min_lot) lot = min_lot;

         double sl = MathRound((ask_price - InpSL_Pips * pip) / tick_size) * tick_size;
         double tp = MathRound((ask_price + InpTP_Pips * pip) / tick_size) * tick_size;

         bool ok = trade.Buy(lot, _Symbol, 0, sl, tp, "FRACTAL_" + pat_name + "_" + grade_name + "_BUY");

         if(ok)
         {
            double fill_price = trade.ResultPrice();

            cnt_fractal_buy++;
            Print("🟢 BUY #", cnt_fractal_buy,
                  " | Fill: ", fill_price, " | Lot: ", lot,
                  " | SL: ", sl, " (-", NormalizeDouble((fill_price - sl)/pip, 0), "p)",
                  " | TP: ", tp, " (+", NormalizeDouble((tp - fill_price)/pip, 0), "p)",
                  " | ", pat_name, " | Grade: ", grade_name,
                  " | Candle: ", candle_confirmed, " | Vix: ", vix_confirmed);
            f_active_pattern = cur_pat;
            last_entry_time = TimeCurrent();
            open_count++;
         }
         else
            Print("❌ BUY FAILED: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }

      if(entry_bear && open_count < InpMaxPositions && !has_any_fractal)
      {
         double lot = CalcLotSize();
         double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(lot < min_lot) lot = min_lot;

         double sl = MathRound((bid_price + InpSL_Pips * pip) / tick_size) * tick_size;
         double tp = MathRound((bid_price - InpTP_Pips * pip) / tick_size) * tick_size;

         bool ok = trade.Sell(lot, _Symbol, 0, sl, tp, "FRACTAL_" + pat_name + "_" + grade_name + "_SELL");

         if(ok)
         {
            double fill_price = trade.ResultPrice();

            cnt_fractal_sell++;
            Print("🔴 SELL #", cnt_fractal_sell,
                  " | Fill: ", fill_price, " | Lot: ", lot,
                  " | SL: ", sl, " (+", NormalizeDouble((sl - fill_price)/pip, 0), "p)",
                  " | TP: ", tp, " (-", NormalizeDouble((fill_price - tp)/pip, 0), "p)",
                  " | ", pat_name, " | Grade: ", grade_name,
                  " | Candle: ", candle_confirmed, " | Vix: ", vix_confirmed);
            f_active_pattern = cur_pat;
            last_entry_time = TimeCurrent();
            open_count++;
         }
         else
            Print("❌ SELL FAILED: ", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      }
   }

}

//+------------------------------------------------------------------+
// Engulfing pattern шалгах
// Bull engulfing: өмнөх улаан лааг бүрэн залгисан ногоон лаа
// Bear engulfing: өмнөх ногоон лааг бүрэн залгисан улаан лаа
//+------------------------------------------------------------------+
bool IsEngulfing(int dir)
{
   double c1_op = GetOpen(1), c1_cl = GetClose(1);
   double c2_op = GetOpen(2), c2_cl = GetClose(2);
   double c1_body = MathAbs(c1_cl - c1_op);
   double c2_body = MathAbs(c2_cl - c2_op);

   if(c1_body < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10) return false;

   if(dir == 1)  // Bull engulfing
   {
      return c2_cl < c2_op                           // өмнөх лаа улаан
          && c1_cl > c1_op                           // одоогийн лаа ногоон
          && c1_cl > MathMax(c2_op, c2_cl)           // body дээд = өмнөхийг давсан
          && c1_op < MathMin(c2_op, c2_cl);          // body доод = өмнөхөөс доор
   }
   else  // Bear engulfing
   {
      return c2_cl > c2_op                           // өмнөх лаа ногоон
          && c1_cl < c1_op                           // одоогийн лаа улаан
          && c1_op > MathMax(c2_op, c2_cl)           // body дээд = өмнөхийг давсан
          && c1_cl < MathMin(c2_op, c2_cl);          // body доод = өмнөхөөс доор
   }
}

//+------------------------------------------------------------------+
// Inside Bar Break шалгах
// IB: bar[2]-ийн high/low-г bar[1] эвдэж чадаагүй
// Break: bar[0] (одоогийн) IB-ийн high/low-г эвдсэн
//+------------------------------------------------------------------+
bool IsInsideBarBreak(int dir)
{
   // bar[2] = mother candle, bar[1] = inside bar
   double mother_hi = GetHigh(2), mother_lo = GetLow(2);
   double ib_hi = GetHigh(1), ib_lo = GetLow(1);

   // Inside bar шалгах: bar[1] нь bar[2] дотор багтсан эсэх
   if(ib_hi > mother_hi || ib_lo < mother_lo) return false;

   double cur_price = dir == 1 ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                               : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(dir == 1)
      return cur_price > mother_hi;   // Bull: mother high-г дээш эвдсэн
   else
      return cur_price < mother_lo;   // Bear: mother low-г доош эвдсэн
}

//+------------------------------------------------------------------+
// 2 лааны шилжилт (Candlestick displacement) — PDF-ийн арга
// 2 том лаа нэг чиглэлд явсан = шилжилт → дараагийх эсрэг лаа ирнэ
//+------------------------------------------------------------------+
bool IsCandleDisplacement(int dir, double atr_val)
{
   double c1_body = MathAbs(GetClose(1) - GetOpen(1));
   double c2_body = MathAbs(GetClose(2) - GetOpen(2));
   double min_body = atr_val * 0.3;

   if(dir == 1)  // Bull entry хүлээж байна → 2 улаан лааны шилжилт доош → буцалт ирнэ
   {
      return GetClose(2) < GetOpen(2) && c2_body > min_body   // bar[2] улаан
          && GetClose(1) < GetOpen(1) && c1_body > min_body;  // bar[1] улаан
   }
   else  // Bear entry → 2 ногоон лааны шилжилт дээш → буцалт ирнэ
   {
      return GetClose(2) > GetOpen(2) && c2_body > min_body   // bar[2] ногоон
          && GetClose(1) > GetOpen(1) && c1_body > min_body;  // bar[1] ногоон
   }
}


//+------------------------------------------------------------------+
// CM Williams Vix Fix — яг TradingView-ийн оригиналтай АДИЛХАН
// study("CM_Williams_Vix_Fix")
// wvf = ((highest(close, pd)-low)/(highest(close, pd)))*100
// col = wvf >= upperBand or wvf >= rangeHigh ? lime : gray
//+------------------------------------------------------------------+
double CalcWVF(int shift)
{
   ENUM_TIMEFRAMES vix_tf = PERIOD_M15;
   double highest_close = 0;
   for(int i = shift; i < shift + InpVixPeriod; i++)
   {
      double cl = iClose(_Symbol, vix_tf, i);
      if(cl > highest_close) highest_close = cl;
   }
   if(highest_close <= 0) return 0;
   double low_val = iLow(_Symbol, vix_tf, shift);
   return ((highest_close - low_val) / highest_close) * 100.0;
}

// Ногоон бар эсэх шалгах (оригинал Pine Script-тэй яг ижил)
// col = wvf >= upperBand or wvf >= rangeHigh ? lime : gray
bool IsVixGreen(int shift)
{
   double wvf = CalcWVF(shift);

   // ── Bollinger Band: upperBand = sma(wvf, bbl) + mult * stdev(wvf, bbl) ──
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

   // ── Percentile: rangeHigh = highest(wvf, lb) * ph ──
   double wvf_highest = 0;
   double wvf_lowest = 99999;
   for(int i = shift; i < shift + InpVixPctLB; i++)
   {
      double w = CalcWVF(i);
      if(w > wvf_highest) wvf_highest = w;
      if(w < wvf_lowest) wvf_lowest = w;
   }
   double rangeHigh = wvf_highest * InpVixPctHi;  // 0.85
   double rangeLow  = wvf_lowest * InpVixPctLo;   // 1.01

   // ── Ногоон = wvf >= upperBand ЭСВЭЛ wvf >= rangeHigh ──
   return (wvf >= upperBand) || (wvf >= rangeHigh);
}

bool IsVixFixSignal(int dir)
{
   if(!InpVixEnable) return true;  // унтраасан бол шүүхгүй

   if(dir == 1)  // BUY: ногоон гарвал = BUY
   {
      // Одоогийн бар эсвэл сүүлийн N бар-д ногоон байсан
      for(int k = 1; k <= InpVixRecent + 1; k++)
      {
         if(IsVixGreen(k)) return true;
      }
      return false;
   }
   else  // SELL: ёроол руу ороод ирвэл (0 руу дөхвөл) = SELL
   {
      double wvf_now = CalcWVF(1);

      // Bollinger midLine тооцоолох
      double sum = 0;
      for(int i = 1; i <= InpVixBBLen; i++)
         sum += CalcWVF(i);
      double midLine = sum / InpVixBBLen;

      // wvf маш бага = ёроол руу ороод ирсэн = SELL
      // Зурган дээрээс харахад бараг харагдахгүй жижиг бар = 0 ойролцоо
      bool near_bottom = wvf_now < midLine * 0.3;

      // Ногоон огт байхгүй
      bool no_green = true;
      for(int k = 1; k <= InpVixRecent + 1; k++)
      {
         if(IsVixGreen(k)) { no_green = false; break; }
      }

      return near_bottom && no_green;
   }
}

//+------------------------------------------------------------------+
// Тодорхой төрлийн позиц байгаа эсэх (comment-р ялгана)
bool HasOpenPosition(ENUM_POSITION_TYPE type, string prefix = "")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol)
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic)
         {
            if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == type)
            {
               if(prefix == "") return true;  // ямар ч позиц
               string comment = PositionGetString(POSITION_COMMENT);
               if(StringFind(comment, prefix) >= 0) return true;  // тодорхой төрөл
            }
         }
      }
   }
   return false;
}

// Нийт нээлттэй позицын тоо
int CountOpenPositions()
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
// 1500 pip ашигтай болоход SL-г BE (entry price) болгох
//+------------------------------------------------------------------+
void CheckBreakEven()
{
   double pip = GetPipSize();
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
      {
         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double profit_pips = (current_price - open_price) / pip;
         // SL аль хэдийн BE дээр байвал алгасах
         if(profit_pips >= InpBE_Pips && current_sl < open_price)
         {
            double be_sl = MathRound(open_price / tick_size) * tick_size;
            if(trade.PositionModify(ticket, be_sl, current_tp))
               Print("🔧 BE | BUY Ticket: ", ticket, " | SL: ", be_sl, " | Profit: ", NormalizeDouble(profit_pips, 0), "p");
         }
      }
      else
      {
         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double profit_pips = (open_price - current_price) / pip;
         // SL аль хэдийн BE дээр байвал алгасах
         if(profit_pips >= InpBE_Pips && current_sl > open_price)
         {
            double be_sl = MathRound(open_price / tick_size) * tick_size;
            if(trade.PositionModify(ticket, be_sl, current_tp))
               Print("🔧 BE | SELL Ticket: ", ticket, " | SL: ", be_sl, " | Profit: ", NormalizeDouble(profit_pips, 0), "p");
         }
      }
   }
}

//+------------------------------------------------------------------+
