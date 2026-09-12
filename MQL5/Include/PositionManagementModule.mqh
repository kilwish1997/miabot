//+------------------------------------------------------------------+
//|                                   PositionManagementModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| CPositionManagementModule Class                                  |
//+------------------------------------------------------------------+
class CPositionManagementModule
{
private:
   string   m_symbol;
   ulong    m_magic;
   double   m_beTriggerR;             // Default 1.2R (prevents normal pullbacks from wiping out trades)
   double   m_beCostBufferPoints;     // Buffer points above entry for cost coverage
   double   m_trailTriggerR;          // Default 1.3R
   double   m_trailATRMultiplier;     // Default 1.5 * ATR (calculated from bar close ATR)
   int      m_timeExitCompletedBars;  // Default 16 completed M15 bars (4 hours)
   
   // Partial exit settings
   bool     m_enablePartialExit;      // Enable partial profit taking
   double   m_partialExitPct;         // Percentage to close (default 50%)
   double   m_partialExitTriggerR;    // Trigger in R for partial exit (default 1.2R)
   double   m_runnerTPMultiplier;     // Extended TP multiplier for remaining runner (e.g. 2.5R)
   ulong    m_partiallyClosedTickets[];// Tickets that have already executed partial close
   
   bool IsPartiallyClosed(ulong ticket)
   {
      int size = ArraySize(m_partiallyClosedTickets);
      for(int i = 0; i < size; i++)
      {
         if(m_partiallyClosedTickets[i] == ticket)
            return true;
      }
      return false;
   }
   
   void MarkPartiallyClosed(ulong ticket)
   {
      int size = ArraySize(m_partiallyClosedTickets);
      ArrayResize(m_partiallyClosedTickets, size + 1);
      m_partiallyClosedTickets[size] = ticket;
   }
   
   // Helper to modify position SL/TP
   bool ModifyPositionSLTP(ulong ticket, double newSL, double newTP)
   {
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = m_symbol;
      request.sl = newSL;
      request.tp = newTP;
      
      ResetLastError();
      bool success = OrderSend(request, result);
      if(!success || result.retcode != TRADE_RETCODE_DONE)
      {
         PrintFormat("[PositionManagement] SL modification failed for ticket %I64u (Retcode %d: %s, SysError %d)", 
                     ticket, result.retcode, result.comment, GetLastError());
         return false;
      }
      PrintFormat("[PositionManagement] Successfully modified SL for ticket %I64u to %.5f (TP: %.5f)", ticket, newSL, newTP);
      return true;
   }
   
   // Helper to close position at market (e.g. for time exit or partial exit)
   bool ClosePositionMarket(ulong ticket, double volume, ENUM_POSITION_TYPE posType, string comment = "TimeExit_16Bars")
   {
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action   = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol   = m_symbol;
      request.volume   = volume;
      request.magic    = m_magic;
      
      MqlTick tick;
      SymbolInfoTick(m_symbol, tick);
      
      if(posType == POSITION_TYPE_BUY)
      {
         request.type  = ORDER_TYPE_SELL;
         request.price = tick.bid;
      }
      else
      {
         request.type  = ORDER_TYPE_BUY;
         request.price = tick.ask;
      }
      
      uint fillingMode = (uint)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      if((fillingMode & SYMBOL_FILLING_FOK) != 0)
         request.type_filling = ORDER_FILLING_FOK;
      else if((fillingMode & SYMBOL_FILLING_IOC) != 0)
         request.type_filling = ORDER_FILLING_IOC;
      else
         request.type_filling = ORDER_FILLING_RETURN;
         
      request.deviation = 10;
      request.comment   = comment;
      
      ResetLastError();
      bool success = OrderSend(request, result);
      if(!success || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED))
      {
         PrintFormat("[PositionManagement] Failed to execute market close on %I64u (Vol: %.2f, Retcode %d: %s)", 
                     ticket, volume, result.retcode, result.comment);
         return false;
      }
      PrintFormat("[PositionManagement] Market close executed on ticket %I64u (Vol: %.2f, Reason: %s)", ticket, volume, comment);
      return true;
   }

public:
   CPositionManagementModule() :
      m_symbol(""),
      m_magic(0),
      m_beTriggerR(1.2),
      m_beCostBufferPoints(2.0),
      m_trailTriggerR(1.3),
      m_trailATRMultiplier(1.5),
      m_timeExitCompletedBars(16),
      m_enablePartialExit(false),
      m_partialExitPct(50.0),
      m_partialExitTriggerR(1.2),
      m_runnerTPMultiplier(2.5)
   {}
   
   void Init(string symbol, ulong magic, double beR = 1.2, double beCostPts = 2.0,
             double trailR = 1.3, double trailATRMult = 1.5, int timeExitBars = 16,
             bool enablePartial = false, double partialPct = 50.0, double partialR = 1.2, double runnerTPMult = 2.5)
   {
      m_symbol = symbol;
      m_magic = magic;
      m_beTriggerR = beR;
      m_beCostBufferPoints = beCostPts;
      m_trailTriggerR = trailR;
      m_trailATRMultiplier = trailATRMult;
      m_timeExitCompletedBars = timeExitBars;
      m_enablePartialExit = enablePartial;
      m_partialExitPct = partialPct;
      m_partialExitTriggerR = partialR;
      m_runnerTPMultiplier = runnerTPMult;
      ArrayResize(m_partiallyClosedTickets, 0);
   }
   
   // Forwarding overload for compatibility
   void ManagePositionsOnTick(double barCloseATR, int digits, double point, double tickSize, int stopsLevel, int freezeLevel)
   {
      OnTickManage(barCloseATR);
   }
   
   // Evaluates and manages open positions on every tick
   void OnTickManage(double currentATR)
   {
      double barCloseATR = currentATR;
      double point     = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      int digits       = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      int stopsLevel   = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      int freezeLevel  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      
      if(point <= 0.0 || tickSize <= 0.0) return;
      
      int totalPositions = PositionsTotal();
      for(int i = totalPositions - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         
         if(PositionGetString(POSITION_SYMBOL) != m_symbol ||
            PositionGetInteger(POSITION_MAGIC) != (long)m_magic)
         {
            continue;
         }
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double volume    = PositionGetDouble(POSITION_VOLUME);
         datetime openTime= (datetime)PositionGetInteger(POSITION_TIME);
         
         MqlTick tick;
         if(!SymbolInfoTick(m_symbol, tick)) continue;
         
         // 1. Time-based Exit Check: completed M15 candles since position opened
         // Calculates actual completed M15 bars after the entry candle closes
         datetime now = TimeTradeServer();
         if(now == 0) now = TimeCurrent();
         int m15Sec = PeriodSeconds(PERIOD_M15);
         datetime entryCandleClose = openTime + (m15Sec - (openTime % m15Sec));
         int completedBars = 0;
         if(now >= entryCandleClose)
            completedBars = 1 + (int)((now - entryCandleClose) / m15Sec);
            
         if(completedBars >= m_timeExitCompletedBars)
         {
            ClosePositionMarket(ticket, volume, posType);
            continue;
         }
         
         // Calculate initial risk distance (R)
         // Note: If initial SL is 0, we cannot calculate R
         if(currentSL <= 0.0) continue;
         
         double initialRiskDist = MathAbs(openPrice - currentSL);
         if(initialRiskDist <= 0.0) continue;
         
         double currentProfitDist = 0.0;
         double minStopDist = MathMax(stopsLevel, freezeLevel) * point;
         double freezeDist  = freezeLevel * point;
         
         if(posType == POSITION_TYPE_BUY)
         {
            currentProfitDist = tick.bid - openPrice;
            double currentR = currentProfitDist / initialRiskDist;
            
            // 0. Optional Partial Exit at 1.2R (e.g. 50% bank profit, run rest to 2.5R)
            if(m_enablePartialExit && !IsPartiallyClosed(ticket) && currentR >= m_partialExitTriggerR)
            {
               double minVol  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
               double stepVol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
               double targetVol = volume * (m_partialExitPct / 100.0);
               double volToClose = MathFloor(targetVol / stepVol) * stepVol;
               double volRemaining = volume - volToClose;
               
               if(volToClose >= minVol && volRemaining >= minVol)
               {
                  if(ClosePositionMarket(ticket, volToClose, posType, "PartialExit_1.2R"))
                  {
                     MarkPartiallyClosed(ticket);
                     volume = volRemaining;
                     
                     // Immediately move SL to Break-Even with cost buffer
                     double costBuffer = m_beCostBufferPoints * point;
                     double beStop = openPrice + costBuffer;
                     double normSL = NormalizeDouble(MathFloor(beStop / tickSize) * tickSize, digits);
                     double newTP = currentTP;
                     if(m_runnerTPMultiplier > 0.0)
                        newTP = NormalizeDouble(openPrice + (m_runnerTPMultiplier * initialRiskDist), digits);
                        
                     if(normSL > currentSL && (tick.bid - normSL) >= minStopDist)
                     {
                        ModifyPositionSLTP(ticket, normSL, newTP);
                        currentSL = normSL;
                        currentTP = newTP;
                     }
                  }
               }
            }
            
            // A. Check Break-Even at +1.2R
            if(currentR >= m_beTriggerR)
            {
               double costBuffer = m_beCostBufferPoints * point;
               double beStop = openPrice + costBuffer;
               
               // Only move UPWARD (never widen/worsen)
               if(beStop > currentSL)
               {
                  // Check stop distance and freeze level against current Bid
                  if((tick.bid - beStop) >= minStopDist && (tick.bid - currentSL) > freezeDist)
                  {
                     double normSL = NormalizeDouble(MathFloor(beStop / tickSize) * tickSize, digits);
                     if(normSL > currentSL)
                     {
                        ModifyPositionSLTP(ticket, normSL, currentTP);
                        currentSL = normSL; // update local
                     }
                  }
               }
            }
            
            // B. Check ATR Trailing Stop at +1.3R (calculated from bar close ATR to eliminate spread jitter)
            if(currentR >= m_trailTriggerR && barCloseATR > 0.0)
            {
               double trailDist = m_trailATRMultiplier * barCloseATR;
               double candidateSL = tick.bid - trailDist;
               
               // Only improve stop upward
               if(candidateSL > currentSL)
               {
                  if((tick.bid - candidateSL) >= minStopDist && (tick.bid - currentSL) > freezeDist)
                  {
                     double normSL = NormalizeDouble(MathFloor(candidateSL / tickSize) * tickSize, digits);
                     if(normSL > currentSL)
                     {
                        ModifyPositionSLTP(ticket, normSL, currentTP);
                        currentSL = normSL;
                     }
                  }
               }
            }
         }
         else // POSITION_TYPE_SELL
         {
            currentProfitDist = openPrice - tick.ask;
            double currentR = currentProfitDist / initialRiskDist;
            
            // 0. Optional Partial Exit at 1.2R (e.g. 50% bank profit, run rest to 2.5R)
            if(m_enablePartialExit && !IsPartiallyClosed(ticket) && currentR >= m_partialExitTriggerR)
            {
               double minVol  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
               double stepVol = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
               double targetVol = volume * (m_partialExitPct / 100.0);
               double volToClose = MathFloor(targetVol / stepVol) * stepVol;
               double volRemaining = volume - volToClose;
               
               if(volToClose >= minVol && volRemaining >= minVol)
               {
                  if(ClosePositionMarket(ticket, volToClose, posType, "PartialExit_1.2R"))
                  {
                     MarkPartiallyClosed(ticket);
                     volume = volRemaining;
                     
                     // Immediately move SL to Break-Even with cost buffer
                     double costBuffer = m_beCostBufferPoints * point;
                     double beStop = openPrice - costBuffer;
                     double normSL = NormalizeDouble(MathCeil(beStop / tickSize) * tickSize, digits);
                     double newTP = currentTP;
                     if(m_runnerTPMultiplier > 0.0)
                        newTP = NormalizeDouble(openPrice - (m_runnerTPMultiplier * initialRiskDist), digits);
                        
                     if((currentSL == 0.0 || normSL < currentSL) && (normSL - tick.ask) >= minStopDist)
                     {
                        ModifyPositionSLTP(ticket, normSL, newTP);
                        currentSL = normSL;
                        currentTP = newTP;
                     }
                  }
               }
            }
            
            // A. Check Break-Even at +1.2R
            if(currentR >= m_beTriggerR)
            {
               double costBuffer = m_beCostBufferPoints * point;
               double beStop = openPrice - costBuffer;
               
               // Only move DOWNWARD (never widen/worsen)
               if(beStop < currentSL || currentSL == 0.0)
               {
                  if((beStop - tick.ask) >= minStopDist && (currentSL - tick.ask) > freezeDist)
                  {
                     double normSL = NormalizeDouble(MathCeil(beStop / tickSize) * tickSize, digits);
                     if(currentSL == 0.0 || normSL < currentSL)
                     {
                        ModifyPositionSLTP(ticket, normSL, currentTP);
                        currentSL = normSL;
                     }
                  }
               }
            }
            
            // B. Check ATR Trailing Stop at +1.3R (calculated from bar close ATR to eliminate spread jitter)
            if(currentR >= m_trailTriggerR && barCloseATR > 0.0)
            {
               double trailDist = m_trailATRMultiplier * barCloseATR;
               double candidateSL = tick.ask + trailDist;
               
               // Only improve stop downward
               if(candidateSL < currentSL || currentSL == 0.0)
               {
                  if((candidateSL - tick.ask) >= minStopDist && (currentSL - tick.ask) > freezeDist)
                  {
                     double normSL = NormalizeDouble(MathCeil(candidateSL / tickSize) * tickSize, digits);
                     if(currentSL == 0.0 || normSL < currentSL)
                     {
                        ModifyPositionSLTP(ticket, normSL, currentTP);
                        currentSL = normSL;
                     }
                  }
               }
            }
         }
      }
   }
};
