//+------------------------------------------------------------------+
//|                               H1TrendM15PullbackBreakoutEA.mq5   |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Include Modular Architecture Components (searches standard MQL5/Include/)
#include <LoggingModule.mqh>
#include <SessionModule.mqh>
#include <NewsModule.mqh>
#include <MarketStructureModule.mqh>
#include <SignalModule.mqh>
#include <RiskModule.mqh>
#include <PositionSizingModule.mqh>
#include <ExecutionModule.mqh>
#include <PositionManagementModule.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== GENERAL SETTINGS ==="
input string   InpTradeSymbol             = "";             // Trade Symbol (Leave empty for chart symbol)
input ulong    InpMagicNumber             = 108151;         // Unique EA Magic Number
input double   InpRiskPercent             = 2.0;            // Risk Per Trade (% of Equity, Max 5.00%)
input bool     InpBlockSymbolLevel        = true;           // Block if other positions exist on this symbol
input int      InpCooldownBars            = 1;              // Cooldown bars after closed trade (M15 bars)
input bool     InpAllowLiveTrading        = false;          // Safety Switch: Allow Live Trading Execution

input group "=== TIMEFRAME & INDICATOR SETTINGS ==="
input int      InpH1FastEMA               = 21;             // H1 Fast Trend EMA Period (Default 21 for Gold)
input int      InpH1SlowEMA               = 55;             // H1 Slow Trend EMA Period (Default 55 for Gold)
input int      InpH1ADXPeriod             = 14;             // H1 ADX Period
input double   InpMinADX                  = 20.0;           // H1 Minimum ADX for Trend Filter
input bool     InpRequireEMASlope         = true;           // H1 Trend: Require EMA Fast Slope Alignment
input bool     InpRequireDMIFilter        = true;           // H1 Trend: Require +DI / -DI Dominance
input int      InpM15PullbackEMA          = 20;             // M15 Pullback EMA Period
input int      InpPullbackLookbackBars    = 5;              // M15 Pullback Lookback Window (Bars 2-N, default 5)
input double   InpPullbackZoneToleranceATR= 0.15;           // M15 Pullback: Zone Tolerance around EMA20 (* ATR)
input bool     InpRequirePullbackRejection= true;           // M15 Pullback: Require Rejection / Resumption Candle
input double   InpMinBreakoutDistATR      = 0.05;           // M15 Breakout: Minimum Breakout Distance (* ATR)
input bool     InpEnableBreakoutRetest    = true;           // M15 Breakout: Enable Breakout-Retest Entry Model
input int      InpM15ATRPeriod            = 14;             // M15 ATR Period
input int      InpATRLookbackBars         = 50;             // ATR Lookback Bars for Median Volatility

input group "=== TRADING SESSION & TIME CONTROLS ==="
input ENUM_SESSION_PROFILE InpSessionProfile = SESSION_PROFILE_FULL_DAY; // Trading Session Profile Preset
input int      InpBrokerServerUTCOffset   = 0;              // Broker Server UTC Offset in Hours (Exness = 0)
input int      InpStartHourUTC            = 8;              // Custom Session Start Hour (UTC) [Gold: 8, Crypto: 7]
input int      InpStartMinUTC             = 0;              // Custom Session Start Minute (UTC)
input int      InpEndHourUTC              = 16;             // Custom Session End Hour (UTC) [Gold: 16, Crypto: 20]
input int      InpEndMinUTC               = 0;              // Custom Session End Minute (UTC)
input bool     InpFilterWeekendCrypto     = true;           // Block Crypto on Weekends (Mon-Fri Only)
input bool     InpEnableRolloverBlock     = true;           // Block entries during rollover
input int      InpRolloverBeforeMins      = 15;             // Rollover Blackout Minutes Before Midnight
input int      InpRolloverAfterMins       = 15;             // Rollover Blackout Minutes After Midnight

input group "=== NEWS FILTER SETTINGS ==="
input bool                  InpEnableNewsFilter        = true;                        // Enable Economic Calendar News Filter
input ENUM_NEWS_FILTER_MODE InpNewsFilterMode          = NEWS_FILTER_ALL_HIGH_IMPACT; // News Filter Scope Mode
input bool                  InpNewsFilterInTester      = false;                       // Enable News Filter in MT5 Strategy Tester
input int                   InpNewsBlackoutBeforeMins  = 30;                          // Blackout Minutes Before High-Impact Event
input int                   InpNewsBlackoutAfterMins   = 30;                          // Blackout Minutes After High-Impact Event
input string                InpNewsCurrency            = "USD";                       // Primary News Currency to Filter

input group "=== RISK & MARGIN CONTROLS ==="
input double   InpMaxRiskMoney            = 15.0;           // Maximum Dollar Risk per Trade ($15 for $500 account)
input double   InpMaxDailyLossMoney       = 30.0;           // Maximum Daily Dollar Loss ($30)
input int      InpMaxDailyLosingTrades    = 2;              // Max Daily Losing Trades (Unlimited trades until 2 SL hit)
input double   InpMaxDailyLossPct         = 6.0;            // Maximum Daily Loss (% of Day-Start Equity)
input double   InpMaxWeeklyLossPct        = 15.0;           // Maximum Weekly Loss (% of Week-Start Equity)
input double   InpDrawdownKillSwitchPct   = 20.0;           // Drawdown Kill Switch (% from Persistent HWM)
input double   InpMaxRequiredMarginPct    = 40.0;           // Maximum Required Margin (% of Equity)
input double   InpMinFreeMarginPct        = 50.0;           // Minimum Post-Trade Free Margin (% of Equity)
input double   InpMinMarginLevelPct       = 200.0;          // Minimum Post-Trade Margin Level (%)
input double   InpExtraCommissionPerLot   = 0.0;            // Estimated Round-Trip Commission ($/Lot)
input double   InpExpectedSlippagePoints  = 2.0;            // Expected Slippage Buffer (Points)

input group "=== EXECUTION & POSITION MANAGEMENT ==="
input double   InpTPMultiplier            = 2.5;            // Take-Profit Multiplier (1:2.5 Risk-to-Reward)
input ulong    InpMaxDeviation            = 10;             // Maximum Slippage Deviation (Points)
input double   InpMaxAdverseDriftATR      = 0.20;           // Max Adverse Price Drift (* ATR)
input double   InpMaxTotalDistanceATR     = 0.40;           // Max Total Price Distance (* ATR)
input double   InpBETriggerR              = 1.5;            // Break-Even Trigger (+R, default 1.5R to avoid pullbacks)
input double   InpBECostBufferPoints      = 2.0;            // Break-Even Cost Buffer (Points above Entry)
input double   InpTrailTriggerR           = 1.8;            // ATR Trailing Stop Trigger (+R)
input double   InpTrailATRMultiplier      = 2.0;            // ATR Trailing Distance Multiplier (* ATR, bar close ATR)
input int      InpTimeExitBars            = 16;             // Time-Based Exit (Completed M15 Bars)
input bool     InpEnablePartialExit       = false;          // Enable Partial Exit at 1.2R (50% Bank, Run to 2.5R)
input double   InpPartialExitPct          = 50.0;           // Partial Exit Percentage (%)
input double   InpPartialExitTriggerR     = 1.2;            // Partial Exit Trigger (+R)
input double   InpPartialRunnerTPMult     = 2.5;            // Extended TP Multiplier for Runner (+R)

//+------------------------------------------------------------------+
//| Module Instances & State Variables                               |
//+------------------------------------------------------------------+
CLoggingModule             Logger;
CSessionModule             Session;
CNewsModule                News;
CMarketStructureModule     Structure;
CSignalModule              Signal;
CRiskModule                Risk;
CPositionSizingModule      Sizing;
CExecutionModule           Execution;
CPositionManagementModule  Management;

string    g_symbol;
datetime  g_lastM15BarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // 1. Resolve Symbol
   g_symbol = InpTradeSymbol;
   if(g_symbol == "")
      g_symbol = _Symbol;
      
   // Ensure symbol is selected in Market Watch
   if(!SymbolSelect(g_symbol, true))
   {
      PrintFormat("[OnInit] Failed to select symbol %s in Market Watch!", g_symbol);
      return INIT_FAILED;
   }
   
   // Check trading mode permission on symbol
   ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_MODE);
   if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      PrintFormat("[OnInit] Trading on symbol %s is currently DISABLED by broker!", g_symbol);
      return INIT_FAILED;
   }
   
   // 2. Validate Safety Constraints & Reject Unsafe Parameter Combinations
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 5.00)
   {
      PrintFormat("[OnInit] FATAL: Configured risk %.2f%% must be > 0.0%% and <= 5.00%%!", InpRiskPercent);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTPMultiplier <= 0.0 || InpTPMultiplier > 10.0)
   {
      PrintFormat("[OnInit] FATAL: TP Multiplier %.2f must be between 0.1 and 10.0!", InpTPMultiplier);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxDailyLossPct <= 0.0 || InpMaxWeeklyLossPct <= 0.0 || InpDrawdownKillSwitchPct <= 0.0)
   {
      Print("[OnInit] FATAL: Daily loss, weekly loss, and drawdown kill switch percentages must be > 0.0%!");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxDailyLossPct > InpMaxWeeklyLossPct)
   {
      PrintFormat("[OnInit] FATAL: Max Daily Loss (%.2f%%) cannot exceed Max Weekly Loss (%.2f%%)!", 
                  InpMaxDailyLossPct, InpMaxWeeklyLossPct);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpTimeExitBars <= 0)
   {
      PrintFormat("[OnInit] FATAL: TimeExitBars (%d) must be greater than zero!", InpTimeExitBars);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMinADX < 0.0)
   {
      PrintFormat("[OnInit] FATAL: MinADX (%.2f) cannot be negative!", InpMinADX);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpPullbackLookbackBars < 2 || InpPullbackLookbackBars > 10)
   {
      PrintFormat("[OnInit] FATAL: PullbackLookbackBars (%d) must be between 2 and 10!", InpPullbackLookbackBars);
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpMaxAdverseDriftATR <= 0.0 || InpMaxTotalDistanceATR <= 0.0 || InpMaxAdverseDriftATR > InpMaxTotalDistanceATR)
   {
      PrintFormat("[OnInit] FATAL: Invalid drift parameters (Adverse: %.2f, Total: %.2f)!", 
                  InpMaxAdverseDriftATR, InpMaxTotalDistanceATR);
      return INIT_PARAMETERS_INCORRECT;
   }
   
   // Print canonical effective configuration
   Print("==================================================================");
   PrintFormat("[OnInit] Canonical Parameters: Risk=%.2f%% | MaxRiskMoney=$%.2f | TPMult=%.2fR", 
               InpRiskPercent, InpMaxRiskMoney, InpTPMultiplier);
   PrintFormat("[OnInit] Protective Limits: DailyLoss=%.2f%% | WeeklyLoss=%.2f%% | DDKillSwitch=%.2f%% | TimeExitBars=%d",
               InpMaxDailyLossPct, InpMaxWeeklyLossPct, InpDrawdownKillSwitchPct, InpTimeExitBars);
   PrintFormat("[OnInit] Step 3 Strategy Enhancements: SessionProfile=%s | NewsMode=%s | PullbackLookback=%d bars | RetestEntry=%s",
               EnumToString(InpSessionProfile), EnumToString(InpNewsFilterMode), InpPullbackLookbackBars, InpEnableBreakoutRetest ? "TRUE" : "FALSE");
   Print("==================================================================");
   
   // Safety switch check for live trading
   if(!MQLInfoInteger(MQL_TESTER) && !InpAllowLiveTrading)
   {
      Print("[OnInit] WARNING: InpAllowLiveTrading is FALSE. The EA will evaluate signals and log CSV, but order placement is disabled.");
   }

   // 3. Initialize Modules
   if(!Logger.Init(g_symbol, InpMagicNumber))
   {
      Print("[OnInit] FATAL: Failed to initialize LoggingModule!");
      return INIT_FAILED;
   }
   
   Session.Init(g_symbol, InpBrokerServerUTCOffset, InpStartHourUTC, InpStartMinUTC, InpEndHourUTC, InpEndMinUTC,
                InpFilterWeekendCrypto, InpEnableRolloverBlock, InpRolloverBeforeMins, InpRolloverAfterMins,
                InpSessionProfile);
                
   News.Init(InpEnableNewsFilter, InpNewsFilterInTester, InpNewsBlackoutBeforeMins, InpNewsBlackoutAfterMins,
             InpNewsCurrency, SymbolInfoString(g_symbol, SYMBOL_CURRENCY_BASE), InpNewsFilterMode);
             
   Structure.Init(g_symbol);
   
   if(!Signal.Init(g_symbol, InpH1FastEMA, InpH1SlowEMA, InpH1ADXPeriod, InpMinADX, 
                   InpM15PullbackEMA, InpM15ATRPeriod, InpATRLookbackBars))
   {
      Print("[OnInit] FATAL: Failed to initialize SignalModule indicator handles!");
      return INIT_FAILED;
   }
   
   Risk.Init(g_symbol, InpMagicNumber, InpMaxDailyLossPct, InpMaxDailyLosingTrades,
             InpMaxWeeklyLossPct, InpDrawdownKillSwitchPct, InpCooldownBars, InpBlockSymbolLevel, InpMaxDailyLossMoney);
             
   if(!Sizing.Init(g_symbol, InpRiskPercent, InpTPMultiplier, InpMaxRequiredMarginPct,
                   InpMinFreeMarginPct, InpMinMarginLevelPct, InpExtraCommissionPerLot, InpExpectedSlippagePoints, InpMaxRiskMoney))
   {
      Print("[OnInit] FATAL: Failed to initialize PositionSizingModule symbol specs!");
      return INIT_FAILED;
   }
   
   Execution.Init(g_symbol, InpMagicNumber, InpMaxDeviation);
   
   Management.Init(g_symbol, InpMagicNumber, InpBETriggerR, InpBECostBufferPoints,
                   InpTrailTriggerR, InpTrailATRMultiplier, InpTimeExitBars,
                   InpEnablePartialExit, InpPartialExitPct, InpPartialExitTriggerR, InpPartialRunnerTPMult);
                   
   // 4. Reconcile Open Positions after startup/restart
   int openCount = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionGetInteger(POSITION_MAGIC) == (long)InpMagicNumber &&
         PositionGetString(POSITION_SYMBOL) == g_symbol)
      {
         openCount++;
         PrintFormat("[OnInit] Reconciled active open position: Ticket %I64u, Type %s, OpenPrice %.5f, SL %.5f, TP %.5f",
                     ticket, EnumToString((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)),
                     PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_SL), PositionGetDouble(POSITION_TP));
      }
   }
   
   PrintFormat("[OnInit] H1TrendM15PullbackBreakoutEA initialized successfully on %s. Active positions: %d", g_symbol, openCount);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Logger.PrintRejectionSummary();
   Signal.Release();
   Logger.Close();
   PrintFormat("[OnDeinit] EA deinitialized. Reason code: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ================================================================
   // PHASE 1: POSITION MANAGEMENT ON EVERY TICK
   // ================================================================
   Risk.UpdateHighWaterMark();
   
   // Fetch latest ATR for trailing stop
   IndicatorSnapshot currentSnap;
   string snapReason = "";
   double currentATR = 0.0;
   if(Signal.FetchSnapshot(currentSnap, snapReason))
   {
      currentATR = currentSnap.currentATR;
   }
   
   Management.ManagePositionsOnTick(currentATR, Sizing.GetDigits(), Sizing.GetPoint(), 
                                    Sizing.GetTickSize(), (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                    (int)SymbolInfoInteger(g_symbol, SYMBOL_TRADE_FREEZE_LEVEL));

   // ================================================================
   // PHASE 2: NEW COMPLETED M15 CANDLE DETECTION
   // ================================================================
   datetime currentM15BarTime = iTime(g_symbol, PERIOD_M15, 0);
   if(currentM15BarTime == 0) return;
   
   // If this bar has already been evaluated or forming candle has not closed, exit
   if(currentM15BarTime == g_lastM15BarTime)
      return;
      
   // Only proceed if a previous bar timestamp was registered (avoids immediate entry on EA launch)
   if(g_lastM15BarTime == 0)
   {
      g_lastM15BarTime = currentM15BarTime;
      return;
   }
   
   // A new M15 candle has just opened!
   g_lastM15BarTime = currentM15BarTime;
   datetime signalBarTime = iTime(g_symbol, PERIOD_M15, 1);
   
   // Prevent duplicate evaluation on same signal bar
   if(!Execution.IsNewSignalBar(signalBarTime))
      return;
   Execution.MarkBarProcessed(signalBarTime);

   // ================================================================
   // PHASE 3: EVALUATION PIPELINE (19 DEFENSIVE CHECKS)
   // ================================================================
   EvaluationLogRecord rec;
   ZeroMemory(rec);
   
   rec.timestamp        = TimeLocal();
   rec.brokerServerTime = TimeCurrent();
   rec.utcTime          = Session.GetCurrentUTCTime(rec.brokerServerTime);
   rec.accountMasked    = Logger.GetMaskedAccount();
   rec.symbol           = g_symbol;
   rec.magic            = InpMagicNumber;
   rec.signalBarTime    = signalBarTime;
   rec.direction        = "NONE";
   rec.rejectionReason  = "";
   
   // 1. Connection Check
   rec.connectionOK = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   if(!rec.connectionOK)
   {
      rec.rejectionReason = "Terminal disconnected from trade server";
      Logger.LogRecord(rec);
      return;
   }
   
   // 2. Market Data & Tick Safety Check
   MqlTick currentTick;
   rec.dataOK = SymbolInfoTick(g_symbol, currentTick);
   if(!rec.dataOK || currentTick.bid <= 0.0 || currentTick.ask <= 0.0)
   {
      rec.rejectionReason = "Market tick data invalid or unavailable";
      Logger.LogRecord(rec);
      return;
   }
   
   // 3. Session Check (UTC Window, Rollover, Broker Session)
   rec.sessionOK = Session.CheckSession(rec.sessionStatus, rec.rejectionReason);
   if(!rec.sessionOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 4. Exposure Check (Max 1 Open Position for EA / Symbol)
   string expStatus = "";
   rec.exposureOK = Risk.CheckExposure(expStatus, rec.rejectionReason);
   if(!rec.exposureOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 5. Cooldown Check (1 Completed M15 Bar)
   if(!Risk.CheckCooldown(signalBarTime, rec.rejectionReason))
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 6. Risk Limits Check (Daily Loss, Losing Trades, Weekly Loss, Drawdown Kill Switch)
   bool dailyOK = false, weeklyOK = false, ddOK = false;
   if(!Risk.CheckRiskLimits(rec.dailyLossStatus, rec.weeklyLossStatus, rec.drawdownStatus,
                            dailyOK, weeklyOK, ddOK, rec.rejectionReason))
   {
      rec.dailyLossOK  = dailyOK;
      rec.weeklyLossOK = weeklyOK;
      rec.drawdownOK   = ddOK;
      Logger.LogRecord(rec);
      return;
   }
   rec.dailyLossOK  = true;
   rec.weeklyLossOK = true;
   rec.drawdownOK   = true;
   
   // 7. News Filter Check
   rec.newsOK = News.IsNewsSafe(rec.newsStatus, rec.rejectionReason);
   if(!rec.newsOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 8. Fetch Indicator Snapshots
   IndicatorSnapshot snap;
   if(!Signal.FetchSnapshot(snap, rec.rejectionReason))
   {
      rec.dataOK = false;
      Logger.LogRecord(rec);
      return;
   }
   
   rec.h1EMA50     = snap.h1EMA50;
   rec.h1EMA200    = snap.h1EMA200;
   rec.h1ADX       = snap.h1ADX;
   rec.m15EMA20    = snap.m15EMA20_1;
   rec.m15ATR      = snap.currentATR;
   rec.medianATR   = snap.medianATR;
   rec.signalClose = snap.m15Close1;
   
   // 9. Volatility Filter Check (0.5 * Median <= ATR <= 2.0 * Median)
   rec.volatilityOK = Signal.CheckVolatility(snap, rec.rejectionReason);
   if(!rec.volatilityOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 10. H1 Trend Alignment Check (with EMA50 slope and +DI/-DI confirmation)
   int trendDir = 0;
   rec.trendOK = Signal.CheckTrend(snap, trendDir, InpRequireEMASlope, InpRequireDMIFilter, rec.rejectionReason);
   if(!rec.trendOK || trendDir == 0)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   bool isLong = (trendDir == 1);
   rec.direction = isLong ? "BUY" : "SELL";
   
   // 11. M15 Pullback Check (EMA20 zone: +0.15 ATR / -0.50 ATR with rejection candle)
   double m15EMABuffer[];
   if(!Signal.GetM15EMA20Buffer(m15EMABuffer, InpPullbackLookbackBars + 2))
   {
      rec.dataOK = false;
      rec.rejectionReason = "Failed to copy M15 EMA buffer for pullback check";
      Logger.LogRecord(rec);
      return;
   }
   
   rec.pullbackOK = Structure.CheckPullback(isLong, m15EMABuffer, snap.currentATR, 
                                           InpPullbackLookbackBars, InpPullbackZoneToleranceATR, InpRequirePullbackRejection, rec.rejectionReason);
   if(!rec.pullbackOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 12. M15 Breakout or Breakout-Retest Trigger Check
   string breakoutReason = "";
   bool isBreakout = Structure.CheckBreakout(isLong, snap.m15Close1, snap.m15EMA20_1, snap.currentATR,
                                            InpMinBreakoutDistATR, breakoutReason);
   bool isRetest = false;
   double retestLevel = 0.0;
   string retestReason = "";
   if(!isBreakout && InpEnableBreakoutRetest)
   {
      isRetest = Structure.CheckBreakoutRetest(isLong, snap.m15Close1, snap.m15EMA20_1, snap.currentATR,
                                              retestLevel, retestReason);
   }
   
   if(!isBreakout && !isRetest)
   {
      rec.breakoutOK = false;
      rec.rejectionReason = InpEnableBreakoutRetest ? 
         StringFormat("No valid breakout (%s) or retest (%s)", breakoutReason, retestReason) : breakoutReason;
      Logger.LogRecord(rec);
      return;
   }
   rec.breakoutOK = true;
   
   // 13. Entry Price & Asymmetric Price Drift Filter
   rec.entryPrice = isLong ? currentTick.ask : currentTick.bid;
   double adverseDrift = 0.0;
   rec.priceDistanceOK = Execution.CheckPriceDistance(isLong, rec.entryPrice, snap.m15Close1, snap.currentATR,
                                                      adverseDrift, InpMaxAdverseDriftATR, InpMaxTotalDistanceATR, rec.rejectionReason);
   if(!rec.priceDistanceOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 14. Swing Level & Stop Loss / Take Profit Calculation
   // For retest, use tighter 3-bar swing; for breakout use 5-bar swing
   int swingBars = isRetest ? 3 : 5;
   double swingLevel = 0.0;
   if(isLong)
   {
      if(!Structure.GetLowestLow(1, swingBars, swingLevel))
      {
         rec.rejectionReason = StringFormat("Failed to retrieve M15 %d-bar swing low", swingBars);
         Logger.LogRecord(rec);
         return;
      }
   }
   else
   {
      if(!Structure.GetHighestHigh(1, swingBars, swingLevel))
      {
         rec.rejectionReason = StringFormat("Failed to retrieve M15 %d-bar swing high", swingBars);
         Logger.LogRecord(rec);
         return;
      }
   }
   
   rec.stopOK = Sizing.CalculateStops(isLong, rec.entryPrice, swingLevel, snap.currentATR,
                                      rec.stopLoss, rec.takeProfit, rec.stopDistance, rec.rejectionReason);
   if(!rec.stopOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 15. Spread Filter Check (<= 10% StopDist and <= 15% ATR)
   rec.spreadOK = Execution.CheckSpread(snap.currentATR, rec.stopDistance, rec.spread, rec.rejectionReason);
   if(!rec.spreadOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 16. Risk & Position Sizing (OrderCalcProfit & strict downward volume rounding)
   ENUM_ORDER_TYPE orderType = isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   rec.riskOK = Sizing.CalculateVolume(orderType, rec.entryPrice, rec.stopLoss,
                                       rec.rawVolume, rec.finalVolume, rec.riskMoney, rec.rejectionReason);
   rec.riskPercentage = Sizing.GetRiskPercent();
   rec.minVolume      = Sizing.GetVolumeMin();
   rec.volumeStep     = Sizing.GetVolumeStep();
   rec.volumeOK       = rec.riskOK;
   
   if(!rec.riskOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 17. Margin Check (OrderCalcMargin)
   rec.marginOK = Sizing.CheckMargin(orderType, rec.finalVolume, rec.entryPrice,
                                     rec.estimatedMargin, rec.rejectionReason);
   if(!rec.marginOK)
   {
      Logger.LogRecord(rec);
      return;
   }
   
   // 18. Pre-Flight OrderCheck()
   rec.orderCheckOK = Execution.ValidateOrderCheck(orderType, rec.finalVolume, rec.entryPrice,
                                                   rec.stopLoss, rec.takeProfit, rec.rejectionReason);
   if(!rec.orderCheckOK)
   {
      Logger.LogRecord(rec);
      return;
   }

   // ================================================================
   // PHASE 4: EXECUTION & LOGGING
   // ================================================================
   if(!InpAllowLiveTrading && !MQLInfoInteger(MQL_TESTER))
   {
      rec.orderRequestResult = "Simulated (Live trading switch is disabled)";
      rec.rejectionReason = "InpAllowLiveTrading is FALSE";
      Logger.LogRecord(rec);
      PrintFormat("[Signal] VALID %s signal on %s at %.5f (SL: %.5f, TP: %.5f, Vol: %.2f) - Live trading disabled.",
                  rec.direction, g_symbol, rec.entryPrice, rec.stopLoss, rec.takeProfit, rec.finalVolume);
      return;
   }
   
   // Send live/tester order
   bool execSuccess = Execution.ExecuteMarketOrder(orderType, rec.finalVolume, rec.entryPrice,
                                                   rec.stopLoss, rec.takeProfit, rec.tradeServerRetcode,
                                                   rec.dealTicket, rec.positionTicket, rec.actualEntryPrice,
                                                   rec.estimatedSlippage, rec.orderRequestResult, rec.rejectionReason);
   rec.actualSpread = rec.spread;
   
   // Write structured CSV record
   Logger.LogRecord(rec);
   
   if(execSuccess)
   {
      PrintFormat("[Execution] ORDER PLACED: %s %s %.2f lots at %.5f | SL: %.5f | TP: %.5f | Ticket: %I64u",
                  rec.direction, g_symbol, rec.finalVolume, rec.actualEntryPrice, rec.stopLoss, rec.takeProfit, rec.dealTicket);
   }
   else
   {
      PrintFormat("[Execution] ORDER FAILED: %s", rec.rejectionReason);
   }
}

//+------------------------------------------------------------------+
//| Trade transaction event for tracking closed trades & executions  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                         const MqlTradeRequest &request,
                         const MqlTradeResult &result)
{
   // Intercept added deals belonging to this EA for full trade reconciliation
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == (long)InpMagicNumber &&
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) == g_symbol)
         {
            ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ulong  posId      = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
            double dealPrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            double dealVol    = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            double dealComm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double dealSwap   = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
            
            if(dealEntry == DEAL_ENTRY_IN)
            {
               PrintFormat("[TradeTransaction: DEAL_IN] Ticket: %I64u | PosID: %I64u | ExecPrice: %.5f | Vol: %.2f | Comm: $%.2f | Swap: $%.2f",
                           dealTicket, posId, dealPrice, dealVol, dealComm, dealSwap);
            }
            else if(dealEntry == DEAL_ENTRY_OUT)
            {
               double netProfit = dealProfit + dealComm + dealSwap;
               Risk.SetLastClosedTradeTime(dealTime);
               PrintFormat("[TradeTransaction: DEAL_OUT] Ticket: %I64u | PosID: %I64u | ExitPrice: %.5f | GrossProfit: $%.2f | Comm: $%.2f | Swap: $%.2f | Net: $%.2f | Time: %s",
                           dealTicket, posId, dealPrice, dealProfit, dealComm, dealSwap, netProfit,
                           TimeToString(dealTime, TIME_DATE | TIME_SECONDS));
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
