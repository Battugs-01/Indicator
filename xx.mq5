//+------------------------------------------------------------------+
//|                                              FractalTBM_EA.mq5   |
//|                                    © Battugs - Fractal + TBM Bot |
//|                          Зөвхөн XAUUSD 5min | SL:100 TP:300     |
//|                     100pip ашигтай болоход 50% хааж BE болгоно    |
//+------------------------------------------------------------------+
#property copyright "Battugs"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- INPUTS
input group "=== Money Management ==="
input double   InpRiskPct     = 2.0;      // Эрсдэлийн хувь (%) — дансны 2%
input int      InpSL_Pips     = 100;      // Stop Loss (pip)
input int      InpTP_Pips     = 300;      // Take Profit (pip) — RR 1:3
input int      InpBE_Pips     = 100;      // Break Even болох pip (100 pip ашигтай болоход)
input double   InpMaxLot      = 1.0;      // Хамгийн их lot (аюулгүй хязгаар)
input double   InpPartialPct  = 50.0;     // Partial close хувь (%)
input int      InpMaxSpread   = 40;       // Хамгийн их спрэд (pip) — энэнээс дээш бол entry нээхгүй
input int      InpMaxPositions = 5;      // Хамгийн их нэгэн зэрэг нээлттэй позиц
input int      InpMagic       = 20260406; // Magic Number

input group "=== Fractal ==="
input int      InpATR_Len     = 14;       // ATR Length
input double   InpDispMult    = 1.5;      // Шилжүүлэгч ATR x
input int      InpLookback    = 20;       // Бүс lookback
input double   InpMaxRange    = 5.0;      // Бүс max range (ATR x)
input int      InpCooldown    = 20;       // Cooldown (bars)

input group "=== TBM ==="
input int      InpSwingLen    = 5;        // Swing Length
input double   InpConfTol     = 2.0;      // Уялдаа tolerance (ATR x)
input double   InpErlizTol    = 5.0;      // Эрлийз threshold (ATR x)
input int      InpMaxFibs     = 4;        // Max Fibo тоо

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

// TBM state
double t_imp_hi = 0, t_imp_lo = 0, t_imp_618 = 0;
int    t_imp_dir = 0;
bool   t_reversed = false;
int    t_last_bar = 0;
double t_last_price = 0;

// Swing arrays
double sh_prices[];  int sh_bars[];   int sh_count = 0;
double sl_prices[];  int sl_bars[];   int sl_count = 0;
bool   new_ph_found = false;  // UpdateSwings-д шинэ PH олдсон эсэх
bool   new_pl_found = false;  // UpdateSwings-д шинэ PL олдсон эсэх

// MOM arrays
double mom_prices[];  double mom_618s[];  double mom_72s[];  int mom_dirs[];
int    mom_count = 0;

// Partial close tracking — ticket-р хянана
ulong  partial_done_tickets[];
int    partial_done_count = 0;

// Entry cooldown (race condition хамгаалалт)
datetime last_entry_time = 0;

// ─── Trade тоолуур ───
int cnt_fractal_buy = 0;
int cnt_fractal_sell = 0;
int cnt_tbm_buy = 0;
int cnt_tbm_sell = 0;
int cnt_tbm_conf_buy = 0;
int cnt_tbm_conf_sell = 0;
int cnt_combined_buy = 0;
int cnt_combined_sell = 0;
int cnt_fractal_disp_bull = 0;
int cnt_fractal_disp_bear = 0;
int cnt_fractal_disp_fail = 0;
int cnt_fractal_pb_start = 0;
int cnt_fractal_pb_expire = 0;
int cnt_tbm_mom_bull = 0;
int cnt_tbm_mom_bear = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);

   atr_handle = iATR(_Symbol, PERIOD_M5, InpATR_Len);
   if(atr_handle == INVALID_HANDLE) return INIT_FAILED;

   ArrayResize(sh_prices, 30); ArrayResize(sh_bars, 30);
   ArrayResize(sl_prices, 30); ArrayResize(sl_bars, 30);
   ArrayResize(mom_prices, 10); ArrayResize(mom_618s, 10);
   ArrayResize(mom_72s, 10); ArrayResize(mom_dirs, 10);
   ArrayResize(partial_done_tickets, 20);

   Print("FractalTBM EA started | Risk: $", GetRiskMoney(), " | SL:", InpSL_Pips, " TP:", InpTP_Pips, " | RR 1:3");
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
   Print("── TBM ──");
   Print("  MOM Bull: ", cnt_tbm_mom_bull, " | Bear: ", cnt_tbm_mom_bear);
   Print("  Entry BUY: ", cnt_tbm_buy, " | SELL: ", cnt_tbm_sell, " | Нийт: ", cnt_tbm_buy + cnt_tbm_sell);
   Print("  Conf BUY: ", cnt_tbm_conf_buy, " | SELL: ", cnt_tbm_conf_sell, " | Нийт: ", cnt_tbm_conf_buy + cnt_tbm_conf_sell);
   Print("── COMBINED ──");
   Print("  Entry BUY: ", cnt_combined_buy, " | SELL: ", cnt_combined_sell, " | Нийт: ", cnt_combined_buy + cnt_combined_sell);
   Print("── НИЙТ ──");
   int total = cnt_fractal_buy + cnt_fractal_sell + cnt_tbm_buy + cnt_tbm_sell
             + cnt_tbm_conf_buy + cnt_tbm_conf_sell + cnt_combined_buy + cnt_combined_sell;
   Print("  Бүх entry: ", total);
   Print("═══════════════════════════════════════════");
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Зөвхөн XAUUSD
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) return;

   // Partial close + BE шалгах (tick бүрд)
   CheckPartialCloseAndBE();

   // Entry шалгах (tick бүрд — 61.8-д хүрсэн мөчид шууд entry)
   double atr_val_rt = GetATR();
   if(atr_val_rt > 0) CheckEntry(atr_val_rt);

   // Fractal + TBM тооцоолол: зөвхөн шинэ 5min лаа дээр
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, PERIOD_M5, 0);
   if(current_bar_time == last_bar_time) return;
   last_bar_time = current_bar_time;

   double atr_val = GetATR();
   if(atr_val <= 0) return;

   UpdateSwings();
   ProcessFractal(atr_val);
   ProcessTBM(atr_val);
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
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = GetRiskMoney();

   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pip_size   = GetPipSize();

   if(tick_size <= 0 || tick_value <= 0) return 0.01;

   // SL = 100 pip = 100 * pip_size (жишээ: 100 * 0.01 = $1.00 зай)
   double sl_price_dist = InpSL_Pips * pip_size;

   // 1 лотод SL-д алдах мөнгө
   double loss_per_lot = (sl_price_dist / tick_size) * tick_value;

   if(loss_per_lot <= 0) return 0.01;

   double lot = risk_money / loss_per_lot;

   // Лотын хязгаарлалт
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / lot_step) * lot_step;

   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;

   // Аюулгүй байдлын хатуу хязгаар — ямар ч тохиолдолд InpMaxLot-с хэтрэхгүй
   if(lot > InpMaxLot)
   {
      Print("⚠️ LOT CAPPED: Тооцоолсон lot=", lot, " → InpMaxLot=", InpMaxLot, " руу бууруулав");
      lot = InpMaxLot;
   }

   // Margin шалгалт — данс дахь мөнгөөр нээж чадах эсэхийг шалгах
   double margin_required = 0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin_required))
   {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin_required > free_margin * 0.8)  // Чөлөөт маржингийн 80%-с ихгүй
      {
         double safe_lot = MathFloor((free_margin * 0.8 / (margin_required / lot)) / lot_step) * lot_step;
         if(safe_lot < min_lot) safe_lot = min_lot;
         Print("⚠️ MARGIN GUARD: lot=", lot, " → safe_lot=", safe_lot, " (margin: $", margin_required, " free: $", free_margin, ")");
         lot = safe_lot;
      }
   }

   Print("Money Management | Balance: $", balance,
         " | Risk: $", risk_money,
         " | SL dist: ", sl_price_dist,
         " | Loss/lot: $", NormalizeDouble(loss_per_lot, 2),
         " | Lot: ", NormalizeDouble(lot, 2));

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

   // ─── Periodic debug (50 бар тутамд) ───
   static int dbg_counter = 0;
   dbg_counter++;
   if(dbg_counter % 50 == 0)
   {
      Print("─── DEBUG #", dbg_counter, " ───",
            " | body: ", NormalizeDouble(body_size, 3),
            " | ATR: ", NormalizeDouble(atr_val, 3),
            " | need: ", NormalizeDouble(atr_val * InpDispMult, 3),
            " | big_bull: ", is_big_bull, " big_bear: ", is_big_bear,
            " | range: ", NormalizeDouble(prev_range, 3),
            " | max_range: ", NormalizeDouble(atr_val * InpMaxRange, 3),
            " | was_ranging: ", was_ranging,
            " | track: ", f_track_state,
            " | disp_dir: ", f_disp_dir,
            " | pb: ", f_pb_started,
            " | pattern: ", f_active_pattern,
            " | cooldown: ", in_cooldown,
            " | sh_count: ", sh_count, " sl_count: ", sl_count,
            " | mom_count: ", mom_count,
            " | t_imp_dir: ", t_imp_dir, " t_reversed: ", t_reversed);
   }

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
         if(disp_range >= zone_range && bars_used <= 10 && disp_range >= zone_range * 0.5)
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
                  " | Extreme: ", f_disp_extreme);
         }
         else
         {
            cnt_fractal_disp_fail++;
            Print("📊 FRACTAL: Bull validate АМЖИЛТГҮЙ ❌ #", cnt_fractal_disp_fail);
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
         if(disp_range >= zone_range && bars_used <= 10 && disp_range >= zone_range * 0.5)
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
                  " | Extreme: ", f_disp_extreme);
         }
         else
         {
            cnt_fractal_disp_fail++;
            Print("📊 FRACTAL: Bear validate АМЖИЛТГҮЙ ❌ #", cnt_fractal_disp_fail);
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
            cnt_fractal_pb_start++;
            Print("📊 FRACTAL: Bull PB эхэллээ #", cnt_fractal_pb_start, " | bars_since_disp: ", f_bars_since_disp);
         }
         if(!f_pb_started && f_bars_since_disp > 10)
         {
            cnt_fractal_pb_expire++;
            Print("📊 FRACTAL: Bull шилжүүлэгч хугацаа дууслаа #", cnt_fractal_pb_expire);
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
            cnt_fractal_pb_start++;
            Print("📊 FRACTAL: Bear PB эхэллээ #", cnt_fractal_pb_start, " | bars_since_disp: ", f_bars_since_disp);
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
void ProcessTBM(double atr_val)
{
   if(sh_count <= 0 || sl_count <= 0) return;

   // ═══ Pine Script-тэй ижил: зөвхөн ШИНЭ pivot олдоход impulse шинэчлэх ═══
   // Pine: if not na(ph) → Bull impulse (шинэ PH + сүүлийн PL)
   if(new_ph_found && sl_count > 0)
   {
      double ph = sh_prices[0];
      double lo = sl_prices[0];
      double rng = ph - lo;
      if(rng > atr_val * 2)
      {
         t_imp_hi = ph;
         t_imp_lo = lo;
         t_imp_618 = lo + rng * 0.618;
         if(t_imp_dir != 1)
         {
            t_reversed = false;
            Print("📊 TBM: Impulse → BULL | rng: ", NormalizeDouble(rng, 2),
                  " | 618: ", NormalizeDouble(t_imp_618, 3), " | reversed reset!");
         }
         t_imp_dir = 1;
      }
   }

   // Pine: if not na(pl) → Bear impulse (шинэ PL + сүүлийн PH)
   if(new_pl_found && sh_count > 0)
   {
      double hi = sh_prices[0];
      double pl = sl_prices[0];
      double rng = hi - pl;
      if(rng > atr_val * 2)
      {
         t_imp_hi = hi;
         t_imp_lo = pl;
         t_imp_618 = hi - rng * 0.618;
         if(t_imp_dir != -1)
         {
            t_reversed = false;
            Print("📊 TBM: Impulse → BEAR | rng: ", NormalizeDouble(rng, 2),
                  " | 618: ", NormalizeDouble(t_imp_618, 3), " | reversed reset!");
         }
         t_imp_dir = -1;
      }
   }

   // ─── Periodic TBM debug (200 бар тутамд) ───
   static int tbm_dbg = 0;
   tbm_dbg++;
   if(tbm_dbg % 200 == 0)
   {
      Print("📊 TBM STATE | dir: ", t_imp_dir,
            " | reversed: ", t_reversed,
            " | 618: ", NormalizeDouble(t_imp_618, 3),
            " | close[1]: ", NormalizeDouble(GetClose(1), 3),
            " | sh:", sh_count, " sl:", sl_count,
            " | mom_count: ", mom_count);
   }

   // Трэнд эргэлт → MOM олох
   if(t_imp_dir == 1 && t_imp_618 > 0 && !t_reversed)
   {
      if(GetClose(1) < t_imp_618 && GetClose(1) < GetOpen(1))
      {
         t_reversed = true;
         // MOM = сүүлийн swing high
         if(sh_count > 0)
            AddMOM(sh_prices[0], t_imp_hi, t_imp_lo, -1, atr_val);
         // 2-р боломж
         if(sh_count >= 2 && sl_count >= 1)
         {
            double mr = sh_prices[1] - sl_prices[0];
            if(mr > atr_val * 2)
               AddMOM(sl_prices[0] + mr * 0.618, t_imp_hi, t_imp_lo, -1, atr_val);
         }
         cnt_tbm_mom_bear++;
         Print("📊 TBM: Bear MOM олдлоо #", cnt_tbm_mom_bear, " | mom_count: ", mom_count, " | imp: ", t_imp_lo, "-", t_imp_hi);
      }
   }

   if(t_imp_dir == -1 && t_imp_618 > 0 && !t_reversed)
   {
      if(GetClose(1) > t_imp_618 && GetClose(1) > GetOpen(1))
      {
         t_reversed = true;
         if(sl_count > 0)
            AddMOM(sl_prices[0], t_imp_lo, t_imp_hi, 1, atr_val);
         if(sl_count >= 2 && sh_count >= 1)
         {
            double mr = sh_prices[0] - sl_prices[1];
            if(mr > atr_val * 2)
               AddMOM(sh_prices[0] - mr * 0.618, t_imp_lo, t_imp_hi, 1, atr_val);
         }
         cnt_tbm_mom_bull++;
         Print("📊 TBM: Bull MOM олдлоо #", cnt_tbm_mom_bull, " | mom_count: ", mom_count, " | imp: ", t_imp_lo, "-", t_imp_hi);
      }
   }
}

//+------------------------------------------------------------------+
void AddMOM(double mom_p, double fib_0, double fib_1, int dir, double atr_val)
{
   double fib_range = MathAbs(fib_1 - fib_0);
   double fib_618 = dir == 1 ? fib_0 + fib_range * 0.618 : fib_0 - fib_range * 0.618;
   double fib_72  = dir == 1 ? fib_0 + fib_range * 0.72  : fib_0 - fib_range * 0.72;
   double dist = MathAbs(fib_618 - mom_p);

   // Эрлийз шүүлтүүр
   if(dist > atr_val * InpErlizTol) return;

   if(mom_count >= 10)
   {
      // Хуучныг устгах
      for(int i = 0; i < 9; i++)
      {
         mom_prices[i] = mom_prices[i+1];
         mom_618s[i] = mom_618s[i+1];
         mom_72s[i] = mom_72s[i+1];
         mom_dirs[i] = mom_dirs[i+1];
      }
      mom_count = 9;
   }
   mom_prices[mom_count] = mom_p;
   mom_618s[mom_count] = fib_618;
   mom_72s[mom_count] = fib_72;
   mom_dirs[mom_count] = dir;
   mom_count++;

   Print("MOM нэмэгдлээ | 61.8: ", fib_618, " | Dir: ", dir == 1 ? "BULL" : "BEAR");
}

//+------------------------------------------------------------------+
void CheckEntry(double atr_val)
{
   int cur_bar = iBars(_Symbol, PERIOD_M5);
   double pip = GetPipSize();
   double bid_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Спрэд шалгах
   double spread_pips = (ask_price - bid_price) / pip;
   if(spread_pips > InpMaxSpread)
      return;

   // Race condition хамгаалалт
   if(TimeCurrent() - last_entry_time < 5)
      return;

   int open_count = CountOpenPositions();

   // Fractal PB идэвхитэй эсэх
   bool f_pb_active = f_disp_dir != 0 && f_pb_started && f_active_pattern == 0;

   // ═══════════════════════════════════════════
   // FRACTAL ENTRY — нэг шилжүүлэгч бүрд 1 entry
   // ═══════════════════════════════════════════
   if(f_pb_active)
   {
      bool has_inner = f_pb_inner_ranging && f_pb_inner_disp;
      int cur_pat = has_inner ? 1 : (f_pb_waves <= 3 ? 2 : 3);

      double recent_hi = MathMax(GetHigh(1), GetHigh(2));
      double recent_lo = MathMin(GetLow(1), GetLow(2));

      bool entry_bull = (f_disp_dir == 1 && bid_price > recent_hi && bid_price > GetOpen(0));
      bool entry_bear = (f_disp_dir == -1 && ask_price < recent_lo && ask_price < GetOpen(0));

      string pat_name = cur_pat == 1 ? "1р" : cur_pat == 2 ? "2р" : "3р";

      if(entry_bull && open_count < InpMaxPositions && !HasOpenPosition(POSITION_TYPE_BUY, "FRACTAL"))
      {
         double entry_price = ask_price;
         double sl = entry_price - InpSL_Pips * pip;
         double tp = entry_price + InpTP_Pips * pip;
         double lot = CalcLotSize();

         if(trade.Buy(lot, _Symbol, 0, sl, tp, "FRACTAL_" + pat_name + "_BUY"))
         {
            cnt_fractal_buy++;
            Print("🟢 FRACTAL BUY #", cnt_fractal_buy, " | ", pat_name, " загвар | Waves: ", f_pb_waves,
                  " | Lot: ", lot, " | Entry: ", entry_price, " | SL: ", sl, " | TP: ", tp);
            f_active_pattern = cur_pat;
            last_entry_time = TimeCurrent();
            open_count++;
         }
      }

      if(entry_bear && open_count < InpMaxPositions && !HasOpenPosition(POSITION_TYPE_SELL, "FRACTAL"))
      {
         double entry_price = bid_price;
         double sl = entry_price + InpSL_Pips * pip;
         double tp = entry_price - InpTP_Pips * pip;
         double lot = CalcLotSize();

         if(trade.Sell(lot, _Symbol, 0, sl, tp, "FRACTAL_" + pat_name + "_SELL"))
         {
            cnt_fractal_sell++;
            Print("🔴 FRACTAL SELL #", cnt_fractal_sell, " | ", pat_name, " загвар | Waves: ", f_pb_waves,
                  " | Lot: ", lot, " | Entry: ", entry_price, " | SL: ", sl, " | TP: ", tp);
            f_active_pattern = cur_pat;
            last_entry_time = TimeCurrent();
            open_count++;
         }
      }
   }

   // ═══════════════════════════════════════════
   // TBM ENTRY: 61.8-д хүрээд буцсан мөчид
   // Нэг MOM бүрд 1 entry, ойр зайд давхар нээхгүй
   // ═══════════════════════════════════════════
   if(mom_count <= 0) return;

   for(int i = 0; i < mom_count; i++)
   {
      double f618 = mom_618s[i];
      int fd = mom_dirs[i];

      // Ижил бүсэд давхар entry нээхгүй (сүүлийн entry-с ATR*1 зай)
      if(t_last_price > 0 && MathAbs(bid_price - t_last_price) < atr_val)
         continue;

      // Уялдаа шалгах
      bool conf = false;
      double zt = MathMax(f618, mom_72s[i]);
      double zb = MathMin(f618, mom_72s[i]);
      double tol = atr_val * InpConfTol;
      if(mom_count >= 2)
      {
         for(int j = 0; j < mom_count; j++)
         {
            if(j != i && mom_prices[j] >= zb - tol && mom_prices[j] <= zt + tol)
               conf = true;
         }
      }

      double cur_low = iLow(_Symbol, PERIOD_M5, 0);
      double cur_high = iHigh(_Symbol, PERIOD_M5, 0);

      // Bull TBM entry
      if(fd == -1 && cur_low <= f618 && bid_price > f618)
      {
         if(open_count >= InpMaxPositions) break;

         bool is_combined = f_pb_active && f_disp_dir == 1;
         double entry_price = ask_price;
         double sl = entry_price - InpSL_Pips * pip;
         double tp = entry_price + InpTP_Pips * pip;
         string comment = is_combined ? "COMBINED_BUY" : (conf ? "TBM_BUY_CONF" : "TBM_BUY");
         double lot = CalcLotSize();

         if(trade.Buy(lot, _Symbol, 0, sl, tp, comment))
         {
            if(is_combined) { cnt_combined_buy++; Print("🟢 ", comment, " #", cnt_combined_buy); }
            else if(conf) { cnt_tbm_conf_buy++; Print("🟢 ", comment, " #", cnt_tbm_conf_buy); }
            else { cnt_tbm_buy++; Print("🟢 ", comment, " #", cnt_tbm_buy); }
            Print("   Lot: ", lot, " | Entry: ", entry_price, " | SL: ", sl, " | TP: ", tp);
            if(is_combined) f_active_pattern = 1;
            t_last_bar = cur_bar;
            t_last_price = entry_price;
            last_entry_time = TimeCurrent();
            open_count++;
            RemoveMOM(i);
         }
         break;
      }

      // Bear TBM entry
      if(fd == 1 && cur_high >= f618 && ask_price < f618)
      {
         if(open_count >= InpMaxPositions) break;

         bool is_combined = f_pb_active && f_disp_dir == -1;
         double entry_price = bid_price;
         double sl = entry_price + InpSL_Pips * pip;
         double tp = entry_price - InpTP_Pips * pip;
         string comment = is_combined ? "COMBINED_SELL" : (conf ? "TBM_SELL_CONF" : "TBM_SELL");
         double lot = CalcLotSize();

         if(trade.Sell(lot, _Symbol, 0, sl, tp, comment))
         {
            if(is_combined) { cnt_combined_sell++; Print("🔴 ", comment, " #", cnt_combined_sell); }
            else if(conf) { cnt_tbm_conf_sell++; Print("🔴 ", comment, " #", cnt_tbm_conf_sell); }
            else { cnt_tbm_sell++; Print("🔴 ", comment, " #", cnt_tbm_sell); }
            Print("   Lot: ", lot, " | Entry: ", entry_price, " | SL: ", sl, " | TP: ", tp);
            if(is_combined) f_active_pattern = 1;
            t_last_bar = cur_bar;
            t_last_price = entry_price;
            last_entry_time = TimeCurrent();
            open_count++;
            RemoveMOM(i);
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
void RemoveMOM(int index)
{
   for(int i = index; i < mom_count - 1; i++)
   {
      mom_prices[i] = mom_prices[i+1];
      mom_618s[i] = mom_618s[i+1];
      mom_72s[i] = mom_72s[i+1];
      mom_dirs[i] = mom_dirs[i+1];
   }
   mom_count--;
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
// 100pip ашигтай болоход: 50% хааж, SL-г BE болгоно
//+------------------------------------------------------------------+
void CleanPartialDoneTickets()
{
   // Хаагдсан позицуудын ticket-г массиваас хасах
   int new_count = 0;
   for(int k = 0; k < partial_done_count; k++)
   {
      bool still_open = false;
      for(int p = PositionsTotal() - 1; p >= 0; p--)
      {
         if(PositionGetSymbol(p) == _Symbol && PositionGetInteger(POSITION_TICKET) == partial_done_tickets[k])
         {
            still_open = true;
            break;
         }
      }
      if(still_open)
      {
         partial_done_tickets[new_count] = partial_done_tickets[k];
         new_count++;
      }
   }
   partial_done_count = new_count;
}

void CheckPartialCloseAndBE()
{
   // Хаагдсан ticket цэвэрлэх (1 минут тутамд)
   static datetime last_clean = 0;
   if(TimeCurrent() - last_clean > 60)
   {
      CleanPartialDoneTickets();
      last_clean = TimeCurrent();
   }

   double pip = GetPipSize();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string comment = PositionGetString(POSITION_COMMENT);

      // Аль хэдийн partial хийсэн эсэх (ticket-р шалгана)
      bool already_done = false;
      for(int k = 0; k < partial_done_count; k++)
      {
         if(partial_done_tickets[k] == ticket) { already_done = true; break; }
      }
      if(already_done) continue;

      double profit_pips = 0;
      if(type == POSITION_TYPE_BUY)
         profit_pips = (SymbolInfoDouble(_Symbol, SYMBOL_BID) - open_price) / pip;
      else
         profit_pips = (open_price - SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / pip;

      // 100pip ашигтай болсон бол
      if(profit_pips >= InpBE_Pips)
      {
         // 50% хаах
         double close_volume = NormalizeDouble(volume * InpPartialPct / 100.0, 2);
         if(close_volume < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
            close_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

         if(close_volume < volume)
         {
            if(trade.PositionClosePartial(ticket, close_volume))
            {
               Print("PARTIAL CLOSE: ", close_volume, " lot хаагдлаа (", InpPartialPct, "%)");

               // SL-г BE болгох (entry price + spread buffer)
               double new_sl = open_price;
               if(type == POSITION_TYPE_BUY)
                  new_sl = open_price + 2 * pip;
               else
                  new_sl = open_price - 2 * pip;

               if(trade.PositionModify(ticket, new_sl, current_tp))
                  Print("SL -> BE: ", new_sl);

               // Энэ ticket-г бүртгэх (дахин partial хийхгүй)
               if(partial_done_count < 20)
               {
                  partial_done_tickets[partial_done_count] = ticket;
                  partial_done_count++;
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
