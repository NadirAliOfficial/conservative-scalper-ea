//+------------------------------------------------------------------+
//|                                        ConservativeScalper.mq4  |
//|                          MT4 Conservative Scalping Expert Advisor|
//|                                                                  |
//|  Strategy:                                                       |
//|    - M15 trend bias via EMA 50/200                               |
//|    - M5 execution via EMA 20 + RSI 14 + candle breakout          |
//|    - Session, spread, ATR, rollover, and day-of-week filters     |
//|    - Fixed-fractional risk sizing (default 0.25% per trade)      |
//|    - Hard SL/TP on every trade — no martingale, no grid          |
//|    - Break-even, trailing stop, time-based exit                  |
//|    - Daily loss cap, max trades/day, consecutive loss pause       |
//|    - Equity drawdown hard stop                                   |
//|                                                                  |
//|  Pairs: EURUSD, GBPUSD, USDJPY (tune per pair)                  |
//|  Timeframe: M5 (with M15 bias)                                   |
//+------------------------------------------------------------------+
#property copyright "NAK"
#property link      "https://github.com/NadirAliOffical/conservative-scalper-ea"
#property version   "1.00"
#property strict

//====================================================================
//  GENERAL INPUTS
//====================================================================
extern int    MagicNumber            = 20260409;   // Unique EA identifier
extern string TradeComment           = "CScalp";   // Order comment tag
extern bool   EnableLong             = true;        // Allow buy trades
extern bool   EnableShort            = true;        // Allow sell trades
extern bool   OneTradePerSymbol      = true;        // One open trade per symbol
extern bool   AllowNewTrades         = true;        // Master on/off switch

//====================================================================
//  SESSION / TIME FILTERS
//====================================================================
extern int    SessionStartHour       = 8;           // Server hour to start trading
extern int    SessionEndHour         = 17;          // Server hour to stop new trades
extern bool   AllowMonday            = true;
extern bool   AllowTuesday           = true;
extern bool   AllowWednesday         = true;
extern bool   AllowThursday          = true;
extern bool   AllowFriday            = false;       // Off by default — thin close
extern int    RolloverBlockBefore    = 30;          // Mins to block before 00:00
extern int    RolloverBlockAfter     = 30;          // Mins to block after  00:00

//====================================================================
//  BIAS INDICATORS  (Higher timeframe)
//====================================================================
extern ENUM_TIMEFRAMES BiasTimeframe = PERIOD_M15;  // Trend filter timeframe
extern int    BiasFastEMA            = 50;           // Fast EMA period on bias TF
extern int    BiasSlowEMA            = 200;          // Slow EMA period on bias TF

//====================================================================
//  EXECUTION INDICATORS  (Chart timeframe — run EA on M5)
//====================================================================
extern int    ExecEMA_Period         = 20;           // EMA for local direction
extern int    RSI_Period             = 14;           // RSI period
extern double RSI_LongLevel          = 50.0;         // RSI cross-above for longs
extern double RSI_ShortLevel         = 50.0;         // RSI cross-below for shorts
extern int    ATR_Period             = 14;           // ATR period
extern double MinATR_Pips            = 3.0;          // Min ATR (pips) — avoid dead mkt
extern int    BreakoutBars           = 1;            // Bars back for high/low breakout

//====================================================================
//  RISK SIZING
//====================================================================
extern int    LotSizingMode          = 1;            // 0=Fixed lot  1=Risk %
extern double FixedLot               = 0.01;         // Used when mode=0
extern double RiskPercent            = 0.50;         // % of equity risked per trade
extern double MaxSpreadPips          = 2.5;          // Max allowed spread in pips
extern int    MaxSlippagePts         = 3;            // Max slippage in broker points

//====================================================================
//  STOP LOSS / TAKE PROFIT
//====================================================================
extern int    StopLossMode           = 1;            // 0=Fixed pips  1=ATR multiple
extern double StopLossPips           = 8.0;          // Fixed SL (pips) mode=0
extern double StopLossATRMult        = 1.2;          // ATR multiplier for SL mode=1
extern int    TakeProfitMode         = 1;            // 0=Fixed pips  1=ATR multiple
extern double TakeProfitPips         = 10.0;         // Fixed TP (pips) mode=0
extern double TakeProfitATRMult      = 1.2;          // ATR multiplier for TP mode=1

//====================================================================
//  TRADE MANAGEMENT
//====================================================================
extern bool   UseBreakEven           = true;
extern double BreakEvenTriggerR      = 0.8;          // Move SL to BE after 0.8R profit
extern double BreakEvenOffsetPips    = 0.5;          // Buffer pips beyond entry for BE
extern bool   UseTrailingStop        = false;
extern double TrailingStartR         = 1.0;          // Start trailing after 1R profit
extern double TrailingDistancePips   = 5.0;          // Trail distance in pips
extern bool   UseTimeExit            = true;
extern int    MaxTradeMinutes        = 20;            // Close stalled trades after N min
extern bool   CloseAtSessionEnd      = true;         // Close open trades at session end

//====================================================================
//  DAILY / SESSION PROTECTION
//====================================================================
extern int    MaxTradesPerDay        = 6;            // Max new trades per session day
extern double MaxDailyLossPercent    = 2.0;          // Stop trading if daily loss >= X%
extern int    MaxConsecutiveLosses   = 3;            // Pause after N consecutive losses
extern double MaxDrawdownPercent     = 20.0;         // Hard stop if equity DD >= X%
extern double MaxTotalOpenRiskPct    = 1.0;          // Cap on total open risk %

//====================================================================
//  NEWS FILTER  (auto-fetches ForexFactory calendar)
//====================================================================
extern bool   UseNewsFilter          = true;         // Enable automatic news filter
extern string NewsFilterCurrencies   = "USD,EUR,GBP";// Block news for these currencies
extern int    NewsBlockMinsBefore    = 30;           // Mins to block before event
extern int    NewsBlockMinsAfter     = 30;           // Mins to block after event
extern int    BrokerGMTOffset        = 2;            // Broker server GMT offset (check chart)

//====================================================================
//  GLOBALS
//====================================================================
double g_pip;                // Value of 1 pip in price units
double g_point;              // Broker point
int    g_digits;             // Symbol digits
int    g_todayTrades;        // Trades opened today
double g_todayStartEquity;   // Equity at start of today
int    g_consecutiveLosses;  // Rolling loss streak count
int    g_lastHistoryTotal;   // History size snapshot (for tracking closed orders)
bool   g_tradingHalted;      // True when max DD hit (persists across days)
double g_peakEquity;         // All-time equity high for DD calculation
datetime g_lastTradeDay;     // Date of last counter reset

// News filter globals
datetime g_newsEvents[];
int      g_newsEventCount  = 0;
datetime g_lastNewsFetch   = 0;
datetime g_lastNewsLogTime = 0;

// GlobalVariable key names (set in OnInit)
string g_gvPeak;
string g_gvHalt;
string g_gvConsec;

//+------------------------------------------------------------------+
//| INIT                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   g_digits = (int)MarketInfo(Symbol(), MODE_DIGITS);

   // Normalise pip for 4-digit and 5-digit brokers
   if(g_digits == 5 || g_digits == 3)
      g_pip = Point * 10;
   else
      g_pip = Point;
   g_point = Point;

   // GlobalVariable keys unique to this symbol + magic number
   string suffix    = Symbol() + "_" + IntegerToString(MagicNumber);
   g_gvPeak         = "CScalp_Peak_"   + suffix;
   g_gvHalt         = "CScalp_Halt_"   + suffix;
   g_gvConsec       = "CScalp_Consec_" + suffix;

   g_todayTrades      = 0;
   g_todayStartEquity = AccountEquity();
   g_lastHistoryTotal = OrdersHistoryTotal();
   g_lastTradeDay     = 0;

   // Restore persistent state so restarts don't reset DD protection
   g_peakEquity        = GlobalVariableCheck(g_gvPeak)   ? GlobalVariableGet(g_gvPeak)        : AccountEquity();
   g_tradingHalted     = GlobalVariableCheck(g_gvHalt)   && GlobalVariableGet(g_gvHalt) > 0;
   g_consecutiveLosses = GlobalVariableCheck(g_gvConsec) ? (int)GlobalVariableGet(g_gvConsec) : 0;

   Log("Initialized | Symbol=" + Symbol() +
       " Digits="  + IntegerToString(g_digits) +
       " Pip="     + DoubleToString(g_pip, g_digits + 1));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Log("Deinitialized | Reason=" + IntegerToString(reason));
}

//+------------------------------------------------------------------+
//| TICK                                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 1. Reset daily counters if calendar date changed
   ResetDailyIfNewDay();

   // 2a. Refresh news calendar once per day
   FetchNewsCalendar();

   // 2. Track peak equity
   if(AccountEquity() > g_peakEquity)
   {
      g_peakEquity = AccountEquity();
      GlobalVariableSet(g_gvPeak, g_peakEquity);
   }

   // 3. Track closed order outcomes (update consecutive loss counter)
   TrackClosedOrders();

   // 4. Manage existing open trades (BE, trail, time/session exit)
   ManageOpenTrades();

   // 5. Evaluate new entry
   if(!CanOpenNewTrade()) return;

   int signal = GetEntrySignal();
   if(signal != 0) ExecuteTrade(signal);
}

//====================================================================
//  DAILY RESET
//====================================================================
void ResetDailyIfNewDay()
{
   datetime today = StringToTime(TimeToStr(TimeCurrent(), TIME_DATE));
   if(today == g_lastTradeDay) return;

   g_lastTradeDay      = today;
   g_todayTrades       = 0;
   g_todayStartEquity  = AccountEquity();

   // Consecutive loss streak is NOT reset on new day — only a win resets it

   Log("New day reset | Equity=" + DoubleToString(AccountEquity(), 2));
}

//====================================================================
//  PRE-TRADE GATE CHECKS
//====================================================================
bool CanOpenNewTrade()
{
   if(!AllowNewTrades)  return false;
   if(g_tradingHalted)  return false;

   // Hard drawdown check
   if(g_peakEquity > 0)
   {
      double dd = (g_peakEquity - AccountEquity()) / g_peakEquity * 100.0;
      if(dd >= MaxDrawdownPercent)
      {
         Log("HARD HALT — max drawdown " + DoubleToString(dd, 2) + "% reached");
         g_tradingHalted = true;
         GlobalVariableSet(g_gvHalt, 1.0);
         return false;
      }
   }

   // Daily loss cap
   if(g_todayStartEquity > 0)
   {
      double dailyLoss = (g_todayStartEquity - AccountEquity()) / g_todayStartEquity * 100.0;
      if(dailyLoss >= MaxDailyLossPercent) return false;
   }

   // Max trades today
   if(g_todayTrades >= MaxTradesPerDay) return false;

   // Consecutive loss pause
   if(g_consecutiveLosses >= MaxConsecutiveLosses) return false;

   // Day of week
   if(!IsAllowedDay()) return false;

   // Session hours
   if(!IsSessionTime()) return false;

   // Rollover block
   if(IsRolloverTime()) return false;

   // News filter
   if(IsNewsTime()) return false;

   // Spread
   double spreadPips = MarketInfo(Symbol(), MODE_SPREAD) * g_point / g_pip;
   if(spreadPips > MaxSpreadPips) return false;

   // ATR minimum (avoid dead market)
   double atrPips = iATR(Symbol(), Period(), ATR_Period, 1) / g_pip;
   if(atrPips < MinATR_Pips) return false;

   // One trade per symbol
   if(OneTradePerSymbol && HasOpenTrade()) return false;

   // Total open risk cap
   if(GetTotalOpenRiskPct() >= MaxTotalOpenRiskPct) return false;

   return true;
}

//====================================================================
//  ENTRY SIGNAL
//  Returns:  1 = BUY   -1 = SELL   0 = NONE
//====================================================================
int GetEntrySignal()
{
   // --- Higher timeframe bias (M15 EMA 50 vs 200) ---
   double biasFast     = iMA(Symbol(), BiasTimeframe, BiasFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double biasSlow     = iMA(Symbol(), BiasTimeframe, BiasSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double biasFastPrev = iMA(Symbol(), BiasTimeframe, BiasFastEMA, 0, MODE_EMA, PRICE_CLOSE, 2);

   bool bullBias = (biasFast > biasSlow) && (biasFast >= biasFastPrev);
   bool bearBias = (biasFast < biasSlow) && (biasFast <= biasFastPrev);

   // --- Execution timeframe indicators ---
   double execEMA  = iMA(Symbol(), Period(), ExecEMA_Period, 0, MODE_EMA, PRICE_CLOSE, 1);
   double rsiNow   = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE, 1);
   double rsiPrev  = iRSI(Symbol(), Period(), RSI_Period, PRICE_CLOSE, 2);

   double prevHigh = iHigh(Symbol(), Period(), BreakoutBars + 1);
   double prevLow  = iLow(Symbol(), Period(), BreakoutBars + 1);
   double closeNow = iClose(Symbol(), Period(), 1);

   // --- LONG ---
   if(EnableLong && bullBias)
   {
      bool aboveEMA  = (closeNow > execEMA);
      bool rsiCross  = (rsiNow >= RSI_LongLevel) && (rsiPrev < RSI_LongLevel);
      bool breakout  = (closeNow > prevHigh);

      if(aboveEMA && rsiCross && breakout) return 1;
   }

   // --- SHORT ---
   if(EnableShort && bearBias)
   {
      bool belowEMA  = (closeNow < execEMA);
      bool rsiCross  = (rsiNow <= RSI_ShortLevel) && (rsiPrev > RSI_ShortLevel);
      bool breakout  = (closeNow < prevLow);

      if(belowEMA && rsiCross && breakout) return -1;
   }

   return 0;
}

//====================================================================
//  EXECUTE TRADE
//====================================================================
void ExecuteTrade(int direction)
{
   double atr = iATR(Symbol(), Period(), ATR_Period, 1);

   // SL distance
   double slDist = (StopLossMode == 0)
                 ? StopLossPips * g_pip
                 : StopLossATRMult * atr;

   // TP distance
   double tpDist = (TakeProfitMode == 0)
                 ? TakeProfitPips * g_pip
                 : TakeProfitATRMult * atr;

   // Enforce broker minimum stop level
   double minStop = MarketInfo(Symbol(), MODE_STOPLEVEL) * g_point;
   if(slDist < minStop + g_pip) slDist = minStop + g_pip;
   if(tpDist < minStop + g_pip) tpDist = minStop + g_pip;

   // Lot size
   double lots = (LotSizingMode == 0)
               ? FixedLot
               : CalcLotByRisk(slDist);
   lots = NormalizeLots(lots);

   if(lots <= 0)
   {
      Log("ERROR: Lot size <=0 — trade skipped");
      return;
   }

   // Free margin check
   double reqMargin = MarketInfo(Symbol(), MODE_MARGINREQUIRED) * lots;
   if(AccountFreeMargin() < reqMargin)
   {
      Log("ERROR: Insufficient margin — trade skipped");
      return;
   }

   double sl, tp;
   int    cmd;
   double price;
   color  arrowCol;

   if(direction == 1)
   {
      cmd      = OP_BUY;
      price    = Ask;
      sl       = NormalizeDouble(price - slDist, g_digits);
      tp       = NormalizeDouble(price + tpDist, g_digits);
      arrowCol = clrDodgerBlue;
   }
   else
   {
      cmd      = OP_SELL;
      price    = Bid;
      sl       = NormalizeDouble(price + slDist, g_digits);
      tp       = NormalizeDouble(price - tpDist, g_digits);
      arrowCol = clrOrangeRed;
   }

   int ticket = OrderSend(Symbol(), cmd, lots, price, MaxSlippagePts,
                          sl, tp, TradeComment, MagicNumber, 0, arrowCol);

   if(ticket < 0)
   {
      Log("ORDER FAILED | Error=" + IntegerToString(GetLastError()) +
          " Dir=" + IntegerToString(direction));
   }
   else
   {
      g_todayTrades++;
      Log("ORDER OPEN | Ticket=" + IntegerToString(ticket) +
          " Dir=" + IntegerToString(direction) +
          " Lots=" + DoubleToString(lots, 2) +
          " Price=" + DoubleToString(price, g_digits) +
          " SL=" + DoubleToString(sl, g_digits) +
          " TP=" + DoubleToString(tp, g_digits) +
          " SLpips=" + DoubleToString(slDist / g_pip, 1));
   }
}

//====================================================================
//  MANAGE OPEN TRADES  (BE, trail, time/session exits)
//====================================================================
void ManageOpenTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol())               continue;
      if(OrderMagicNumber() != MagicNumber)       continue;
      if(OrderType() > OP_SELL)                   continue; // skip pending

      int    ticket    = OrderTicket();
      int    type      = OrderType();
      double openPrice = OrderOpenPrice();
      double curSL     = OrderStopLoss();
      double curTP     = OrderTakeProfit();
      double slDist    = MathAbs(openPrice - curSL);

      // --- Session-end close ---
      if(CloseAtSessionEnd && !IsSessionTime())
      {
         CloseOrder(ticket, type, "SessionEnd");
         continue;
      }

      // --- Time-based exit ---
      if(UseTimeExit)
      {
         int minsOpen = (int)((TimeCurrent() - OrderOpenTime()) / 60);
         if(minsOpen >= MaxTradeMinutes)
         {
            CloseOrder(ticket, type, "TimeExit");
            continue;
         }
      }

      // Current P&L in price units
      double profit = (type == OP_BUY)
                    ? Bid - openPrice
                    : openPrice - Ask;
      double profitR = (slDist > 0) ? profit / slDist : 0;

      // --- Break-even ---
      if(UseBreakEven && slDist > 0 && profitR >= BreakEvenTriggerR)
      {
         double beOffset = BreakEvenOffsetPips * g_pip;
         if(type == OP_BUY)
         {
            double newSL = NormalizeDouble(openPrice + beOffset, g_digits);
            if(newSL > curSL + g_point)
            {
               if(OrderModify(ticket, openPrice, newSL, curTP, 0, clrGold))
                  Log("BE set | Ticket=" + IntegerToString(ticket) +
                      " NewSL=" + DoubleToString(newSL, g_digits));
            }
         }
         else
         {
            double newSL = NormalizeDouble(openPrice - beOffset, g_digits);
            if(curSL == 0 || newSL < curSL - g_point)
            {
               if(OrderModify(ticket, openPrice, newSL, curTP, 0, clrGold))
                  Log("BE set | Ticket=" + IntegerToString(ticket) +
                      " NewSL=" + DoubleToString(newSL, g_digits));
            }
         }
      }

      // --- Trailing stop ---
      if(UseTrailingStop && slDist > 0 && profitR >= TrailingStartR)
      {
         double trailDist = TrailingDistancePips * g_pip;
         if(type == OP_BUY)
         {
            double newSL = NormalizeDouble(Bid - trailDist, g_digits);
            if(newSL > curSL + g_point)
            {
               if(OrderModify(ticket, openPrice, newSL, curTP, 0, clrAqua))
                  Log("Trail updated | Ticket=" + IntegerToString(ticket) +
                      " NewSL=" + DoubleToString(newSL, g_digits));
            }
         }
         else
         {
            double newSL = NormalizeDouble(Ask + trailDist, g_digits);
            if(curSL == 0 || newSL < curSL - g_point)
            {
               if(OrderModify(ticket, openPrice, newSL, curTP, 0, clrAqua))
                  Log("Trail updated | Ticket=" + IntegerToString(ticket) +
                      " NewSL=" + DoubleToString(newSL, g_digits));
            }
         }
      }
   }
}

//====================================================================
//  TRACK CLOSED ORDERS  (update consecutive loss counter)
//====================================================================
void TrackClosedOrders()
{
   int histTotal = OrdersHistoryTotal();
   if(histTotal <= g_lastHistoryTotal) return;

   for(int i = g_lastHistoryTotal; i < histTotal; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol()       != Symbol())        continue;
      if(OrderMagicNumber()  != MagicNumber)     continue;
      if(OrderType()         >  OP_SELL)         continue;

      double netPnl = OrderProfit() + OrderSwap() + OrderCommission();

      if(netPnl < 0)
      {
         g_consecutiveLosses++;
         GlobalVariableSet(g_gvConsec, (double)g_consecutiveLosses);
         Log("LOSS | Ticket=" + IntegerToString(OrderTicket()) +
             " PnL=" + DoubleToString(netPnl, 2) +
             " ConsecLosses=" + IntegerToString(g_consecutiveLosses));
      }
      else
      {
         if(g_consecutiveLosses > 0)
            Log("WIN — loss streak reset from " + IntegerToString(g_consecutiveLosses));
         g_consecutiveLosses = 0;
         GlobalVariableSet(g_gvConsec, 0.0);
      }
   }
   g_lastHistoryTotal = histTotal;
}

//====================================================================
//  CLOSE ORDER HELPER
//====================================================================
void CloseOrder(int ticket, int type, string reason)
{
   double price = (type == OP_BUY) ? Bid : Ask;
   bool ok = OrderClose(ticket, OrderLots(), price, MaxSlippagePts, clrWhite);

   if(ok)
      Log("ORDER CLOSED | Ticket=" + IntegerToString(ticket) + " Reason=" + reason);
   else
      Log("CLOSE FAILED | Ticket=" + IntegerToString(ticket) +
          " Error=" + IntegerToString(GetLastError()));
}

//====================================================================
//  POSITION SIZING
//====================================================================
double CalcLotByRisk(double slDist)
{
   double equity    = AccountEquity();
   double riskAmt   = equity * RiskPercent / 100.0;
   double tickVal   = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickVal <= 0 || tickSize <= 0 || slDist <= 0) return FixedLot;

   double slTicks = slDist / tickSize;
   return riskAmt / (slTicks * tickVal);
}

double NormalizeLots(double lots)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(lotStep > 0)
      lots = MathFloor(lots / lotStep) * lotStep;

   return NormalizeDouble(MathMax(minLot, MathMin(maxLot, lots)), 2);
}

//====================================================================
//  UTILITY FUNCTIONS
//====================================================================
bool HasOpenTrade()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         return true;
   }
   return false;
}

double GetTotalOpenRiskPct()
{
   double totalRisk = 0;
   double equity    = AccountEquity();
   if(equity <= 0) return 0;

   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      if(OrderType() > OP_SELL)             continue;

      double sl = OrderStopLoss();
      if(sl == 0) continue;

      double slDist   = MathAbs(OrderOpenPrice() - sl);
      double tickVal  = MarketInfo(OrderSymbol(), MODE_TICKVALUE);
      double tickSize = MarketInfo(OrderSymbol(), MODE_TICKSIZE);
      if(tickSize <= 0) continue;

      totalRisk += (slDist / tickSize) * tickVal * OrderLots() / equity * 100.0;
   }
   return totalRisk;
}

bool IsSessionTime()
{
   int h = TimeHour(TimeCurrent());
   return (h >= SessionStartHour && h < SessionEndHour);
}

bool IsRolloverTime()
{
   int h = TimeHour(TimeCurrent());
   int m = TimeMinute(TimeCurrent());
   int totalMin = h * 60 + m;

   // Minutes until next midnight
   int beforeMid = 1440 - totalMin;
   // Minutes since last midnight
   int afterMid  = totalMin;

   return (beforeMid <= RolloverBlockBefore || afterMid <= RolloverBlockAfter);
}

bool IsAllowedDay()
{
   int dow = TimeDayOfWeek(TimeCurrent());
   switch(dow)
   {
      case 1: return AllowMonday;
      case 2: return AllowTuesday;
      case 3: return AllowWednesday;
      case 4: return AllowThursday;
      case 5: return AllowFriday;
      default: return false;
   }
}

//====================================================================
//  NEWS FILTER — auto-fetches ForexFactory high-impact calendar
//  Requires: MT4 Tools → Options → Expert Advisors →
//            Allow WebRequest for: https://nfs.faireconomy.media
//====================================================================
void FetchNewsCalendar()
{
   if(!UseNewsFilter) return;

   datetime today = StringToTime(TimeToStr(TimeCurrent(), TIME_DATE));
   if(g_lastNewsFetch == today) return;  // Already fetched today

   string url     = "https://nfs.faireconomy.media/ff_calendar_thisweek.json";
   string headers = "User-Agent: Mozilla/5.0\r\n";
   char   post[];
   char   result[];
   string resultHeaders;

   ResetLastError();
   int httpCode = WebRequest("GET", url, headers, 10000, post, result, resultHeaders);

   if(httpCode != 200)
   {
      Log("NEWS: Fetch failed. HTTP=" + IntegerToString(httpCode) +
          " Error=" + IntegerToString(GetLastError()) +
          " — Check WebRequest whitelist in MT4 options");
      return;
   }

   string json = CharArrayToString(result);
   ParseNewsJSON(json);
   g_lastNewsFetch = today;
   Log("NEWS: Calendar updated. High-impact events found=" + IntegerToString(g_newsEventCount));
}

void ParseNewsJSON(string json)
{
   g_newsEventCount = 0;
   ArrayResize(g_newsEvents, 200);

   int pos = 0;
   int jsonLen = StringLen(json);

   while(pos < jsonLen)
   {
      // Find next JSON object
      int objStart = StringFind(json, "{", pos);
      if(objStart < 0) break;
      int objEnd = StringFind(json, "}", objStart);
      if(objEnd < 0) break;

      string obj = StringSubstr(json, objStart, objEnd - objStart + 1);

      // Only process High impact events
      if(StringFind(obj, "\"impact\":\"High\"") >= 0)
      {
         // Check currency filter
         string country = ExtractJSONString(obj, "country");
         if(StringFind(NewsFilterCurrencies, country) >= 0)
         {
            // Parse date
            string dateStr = ExtractJSONString(obj, "date");
            datetime eventTime = ParseISODate(dateStr);
            if(eventTime > 0 && g_newsEventCount < 200)
            {
               g_newsEvents[g_newsEventCount] = eventTime;
               g_newsEventCount++;
               string title = ExtractJSONString(obj, "title");
               Log("NEWS: Loaded | " + country + " " + title +
                   " @ " + TimeToStr(eventTime, TIME_DATE | TIME_MINUTES));
            }
         }
      }
      pos = objEnd + 1;
   }
   ArrayResize(g_newsEvents, g_newsEventCount);
}

string ExtractJSONString(string obj, string key)
{
   string search = "\"" + key + "\":\"";
   int start = StringFind(obj, search);
   if(start < 0) return "";
   start += StringLen(search);
   int end = StringFind(obj, "\"", start);
   if(end < 0) return "";
   return StringSubstr(obj, start, end - start);
}

datetime ParseISODate(string iso)
{
   // Format: "2026-04-04T08:30:00-0400"
   if(StringLen(iso) < 19) return 0;

   int year  = (int)StringToInteger(StringSubstr(iso, 0, 4));
   int month = (int)StringToInteger(StringSubstr(iso, 5, 2));
   int day   = (int)StringToInteger(StringSubstr(iso, 8, 2));
   int hour  = (int)StringToInteger(StringSubstr(iso, 11, 2));
   int min   = (int)StringToInteger(StringSubstr(iso, 14, 2));

   // Parse timezone offset (e.g. -0400 or +0000)
   int tzOffsetSecs = 0;
   int tzPos = StringFind(iso, "+", 19);
   int tzSign = 1;
   if(tzPos < 0) { tzPos = StringFind(iso, "-", 19); tzSign = -1; }
   if(tzPos >= 0)
   {
      int tzH = (int)StringToInteger(StringSubstr(iso, tzPos + 1, 2));
      int tzM = (int)StringToInteger(StringSubstr(iso, tzPos + 3, 2));
      tzOffsetSecs = tzSign * (tzH * 3600 + tzM * 60);
   }

   // Build UTC datetime
   string dtStr = StringFormat("%04d.%02d.%02d %02d:%02d", year, month, day, hour, min);
   datetime utc  = StringToTime(dtStr) - tzOffsetSecs;

   // Convert UTC → broker server time
   datetime serverTime = utc + BrokerGMTOffset * 3600;
   return serverTime;
}

bool IsNewsTime()
{
   if(!UseNewsFilter || g_newsEventCount == 0) return false;

   datetime now        = TimeCurrent();
   int      blockBefore = NewsBlockMinsBefore * 60;
   int      blockAfter  = NewsBlockMinsAfter  * 60;

   for(int i = 0; i < g_newsEventCount; i++)
   {
      if(now >= g_newsEvents[i] - blockBefore &&
         now <= g_newsEvents[i] + blockAfter)
      {
         if(g_newsEvents[i] != g_lastNewsLogTime)
         {
            Log("NEWS: Trading blocked near event @ " +
                TimeToStr(g_newsEvents[i], TIME_DATE | TIME_MINUTES));
            g_lastNewsLogTime = g_newsEvents[i];
         }
         return true;
      }
   }
   return false;
}

void Log(string msg)
{
   Print("[CScalp] " + TimeToStr(TimeCurrent(), TIME_DATE | TIME_MINUTES) + " | " + msg);
}
//+------------------------------------------------------------------+
