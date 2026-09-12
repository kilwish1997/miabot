//+------------------------------------------------------------------+
//|                                                   RiskModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| CRiskModule Class                                                |
//+------------------------------------------------------------------+
class CRiskModule
{
private:
   string   m_symbol;
   ulong    m_magic;
   double   m_maxDailyLossPct;        // default 1.0%
   double   m_maxDailyLossMoney;      // default $50.0
   int      m_maxDailyLosingTrades;   // default 2 (unlimited until 2 SL hit)
   double   m_maxWeeklyLossPct;       // default 3.0%
   double   m_drawdownKillSwitchPct;  // default 5.0%
   int      m_cooldownBars;           // default 1 completed M15 bar
   bool     m_blockSymbolLevel;       // block if any position on symbol exists
   
   // State tracking
   datetime m_currentDayStart;
   datetime m_currentWeekStart;
   double   m_dayStartEquity;
   double   m_weekStartEquity;
   double   m_highWaterMark;
   string   m_gvHWMName;
   datetime m_lastClosedTradeTime;    // Timestamp of last closed trade for cooldown
   
   // Calculates day start (00:00 server time)
   datetime GetDayStart(datetime t)
   {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      return StructToTime(dt);
   }
   
   // Calculates Monday 00:00 server time
   datetime GetWeekStart(datetime t)
   {
      MqlDateTime dt;
      TimeToStruct(t, dt);
      // Sunday=0, Monday=1, ..., Saturday=6
      int daysSinceMon = (dt.day_of_week == 0) ? 6 : (dt.day_of_week - 1);
      datetime dayStart = GetDayStart(t);
      return dayStart - (daysSinceMon * 86400);
   }
   
   void LoadOrInitHWM()
   {
      m_gvHWMName = "EA_HWM_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + IntegerToString(m_magic);
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      if(GlobalVariableCheck(m_gvHWMName))
      {
         m_highWaterMark = GlobalVariableGet(m_gvHWMName);
         if(currentEquity > m_highWaterMark)
         {
            m_highWaterMark = currentEquity;
            GlobalVariableSet(m_gvHWMName, m_highWaterMark);
         }
      }
      else
      {
         m_highWaterMark = currentEquity;
         GlobalVariableSet(m_gvHWMName, m_highWaterMark);
      }
      PrintFormat("[RiskModule] Persistent High-Water Mark: $%.2f (GV: %s)", m_highWaterMark, m_gvHWMName);
   }

public:
   CRiskModule() :
      m_symbol(""),
      m_magic(0),
      m_maxDailyLossPct(1.0),
      m_maxDailyLossMoney(50.0),
      m_maxDailyLosingTrades(2),
      m_maxWeeklyLossPct(3.0),
      m_drawdownKillSwitchPct(5.0),
      m_cooldownBars(1),
      m_blockSymbolLevel(true),
      m_currentDayStart(0),
      m_currentWeekStart(0),
      m_dayStartEquity(0.0),
      m_weekStartEquity(0.0),
      m_highWaterMark(0.0),
      m_lastClosedTradeTime(0)
   {}
   
   void Init(string symbol, ulong magic, double maxDailyLoss = 1.0, int maxLosingTrades = 2,
             double maxWeeklyLoss = 3.0, double maxDrawdown = 5.0, int cooldownBars = 1, bool blockSymbol = true,
             double maxDailyLossMoney = 50.0)
   {
      m_symbol = symbol;
      m_magic = magic;
      m_maxDailyLossPct = maxDailyLoss;
      m_maxDailyLossMoney = maxDailyLossMoney;
      m_maxDailyLosingTrades = maxLosingTrades;
      m_maxWeeklyLossPct = maxWeeklyLoss;
      m_drawdownKillSwitchPct = maxDrawdown;
      m_cooldownBars = cooldownBars;
      m_blockSymbolLevel = blockSymbol;
      
      datetime now = TimeCurrent();
      m_currentDayStart = GetDayStart(now);
      m_currentWeekStart = GetWeekStart(now);
      
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dayStartEquity = currentEquity;
      m_weekStartEquity = currentEquity;
      
      LoadOrInitHWM();
   }
   
   // Update HWM on every tick
   void UpdateHighWaterMark()
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(currentEquity > m_highWaterMark)
      {
         m_highWaterMark = currentEquity;
         GlobalVariableSet(m_gvHWMName, m_highWaterMark);
      }
   }
   
   // Roll day/week boundaries if server time advanced
   void RefreshPeriods()
   {
      datetime now = TimeCurrent();
      datetime dayStart = GetDayStart(now);
      datetime weekStart = GetWeekStart(now);
      
      if(dayStart != m_currentDayStart)
      {
         m_currentDayStart = dayStart;
         m_dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         PrintFormat("[RiskModule] New broker day started. Day-start equity reset to $%.2f", m_dayStartEquity);
      }
      
      if(weekStart != m_currentWeekStart)
      {
         m_currentWeekStart = weekStart;
         m_weekStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         PrintFormat("[RiskModule] New broker week started. Week-start equity reset to $%.2f", m_weekStartEquity);
      }
   }
   
   // Checks exposure (max 1 open position for EA, max 1 open position on symbol)
   bool CheckExposure(string &statusStr, string &rejectionReason)
   {
      int eaPositions = 0;
      int symbolPositions = 0;
      
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         long posMagic = PositionGetInteger(POSITION_MAGIC);
         
         if(posMagic == (long)m_magic)
            eaPositions++;
            
         if(posSymbol == m_symbol)
            symbolPositions++;
      }
      
      if(eaPositions >= 1)
      {
         statusStr = "ExistingEAPosition";
         rejectionReason = "EA already has an active open position";
         return false;
      }
      
      if(m_blockSymbolLevel && symbolPositions >= 1)
      {
         statusStr = "ExistingSymbolPosition";
         rejectionReason = "Symbol " + m_symbol + " already has an active position";
         return false;
      }
      
      statusStr = "ExposureClear";
      rejectionReason = "";
      return true;
   }
   
   // Checks cooldown after last closed trade (1 completed M15 bar)
   bool CheckCooldown(datetime signalBarTime, string &rejectionReason)
   {
      if(m_cooldownBars <= 0 || m_lastClosedTradeTime == 0) return true;
      
      // If the trade was closed in the previous M15 bar or current bar, enforce cooldown
      // Duration of cooldown = m_cooldownBars * 900 seconds
      if((signalBarTime - m_lastClosedTradeTime) < (m_cooldownBars * 900))
      {
         rejectionReason = StringFormat("Cooldown active: last trade closed at %s, need %d completed bar", 
                                        TimeToString(m_lastClosedTradeTime, TIME_DATE | TIME_MINUTES), m_cooldownBars);
         return false;
      }
      return true;
   }
   
   void SetLastClosedTradeTime(datetime t)
   {
      m_lastClosedTradeTime = t;
   }
   
   // Evaluates Daily Loss, Losing Trades, Weekly Loss, and Drawdown Kill Switch
   bool CheckRiskLimits(string &dailyStatus, string &weeklyStatus, string &ddStatus,
                        bool &dailyOK, bool &weeklyOK, bool &ddOK, string &rejectionReason)
   {
      RefreshPeriods();
      UpdateHighWaterMark();
      
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      // 1. Calculate realized losses today for this EA
      HistorySelect(m_currentDayStart, TimeCurrent());
      int dealsTotal = HistoryDealsTotal();
      double dailyRealizedLoss = 0.0;
      int losingTradesToday = 0;
      
      for(int i = 0; i < dealsTotal; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if(dealTicket == 0) continue;
         
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == (long)m_magic &&
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) == m_symbol &&
            HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
         {
            double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                            HistoryDealGetDouble(dealTicket, DEAL_COMMISSION) +
                            HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            if(profit < 0)
            {
               dailyRealizedLoss += MathAbs(profit);
               losingTradesToday++;
            }
         }
      }
      
      // Total daily loss combines equity drop from day-start and realized loss
      double equityDropToday = (m_dayStartEquity > currentEquity) ? (m_dayStartEquity - currentEquity) : 0.0;
      double totalDailyLossMoney = MathMax(equityDropToday, dailyRealizedLoss);
      double currentDailyLossPct = (m_dayStartEquity > 0) ? (totalDailyLossMoney / m_dayStartEquity * 100.0) : 0.0;
      
      dailyStatus = StringFormat("Loss: $%.2f (Max $%.2f) | Losses: %d/Max %d", 
                                 totalDailyLossMoney, m_maxDailyLossMoney, losingTradesToday, m_maxDailyLosingTrades);
      
      if(m_maxDailyLossMoney > 0 && totalDailyLossMoney >= m_maxDailyLossMoney)
      {
         dailyOK = false;
         rejectionReason = StringFormat("Daily dollar loss limit reached ($%.2f >= $%.2f)", totalDailyLossMoney, m_maxDailyLossMoney);
         return false;
      }
      if(m_maxDailyLossPct > 0 && currentDailyLossPct >= m_maxDailyLossPct)
      {
         dailyOK = false;
         rejectionReason = StringFormat("Daily loss limit exceeded (%.2f%% >= %.2f%%)", currentDailyLossPct, m_maxDailyLossPct);
         return false;
      }
      if(losingTradesToday >= m_maxDailyLosingTrades)
      {
         dailyOK = false;
         rejectionReason = StringFormat("Max daily losing trades reached (%d >= %d)", losingTradesToday, m_maxDailyLosingTrades);
         return false;
      }
      dailyOK = true;
      
      // 2. Weekly Loss Check
      double equityDropWeek = (m_weekStartEquity > currentEquity) ? (m_weekStartEquity - currentEquity) : 0.0;
      double currentWeeklyLossPct = (m_weekStartEquity > 0) ? (equityDropWeek / m_weekStartEquity * 100.0) : 0.0;
      weeklyStatus = StringFormat("Loss: %.2f%% / Max: %.2f%%", currentWeeklyLossPct, m_maxWeeklyLossPct);
      
      if(currentWeeklyLossPct >= m_maxWeeklyLossPct)
      {
         weeklyOK = false;
         rejectionReason = StringFormat("Weekly loss limit exceeded (%.2f%% >= %.2f%%)", currentWeeklyLossPct, m_maxWeeklyLossPct);
         return false;
      }
      weeklyOK = true;
      
      // 3. Drawdown Kill Switch (from persistent HWM)
      double drawdownMoney = (m_highWaterMark > currentEquity) ? (m_highWaterMark - currentEquity) : 0.0;
      double currentDDPct = (m_highWaterMark > 0) ? (drawdownMoney / m_highWaterMark * 100.0) : 0.0;
      ddStatus = StringFormat("DD: %.2f%% / Max: %.2f%% (HWM: $%.2f)", currentDDPct, m_drawdownKillSwitchPct, m_highWaterMark);
      
      if(currentDDPct >= m_drawdownKillSwitchPct)
      {
         ddOK = false;
         rejectionReason = StringFormat("Drawdown kill switch active (%.2f%% >= %.2f%% from HWM $%.2f)", 
                                        currentDDPct, m_drawdownKillSwitchPct, m_highWaterMark);
         return false;
      }
      ddOK = true;
      
      rejectionReason = "";
      return true;
   }
   
   double GetHighWaterMark() { return m_highWaterMark; }
};
