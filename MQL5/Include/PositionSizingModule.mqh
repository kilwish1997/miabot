//+------------------------------------------------------------------+
//|                                         PositionSizingModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| CPositionSizingModule Class                                      |
//+------------------------------------------------------------------+
class CPositionSizingModule
{
private:
   string   m_symbol;
   double   m_riskPercent;            // Default 0.25%, max 0.50%
   double   m_tpMultiplier;           // Default 1.8R
   double   m_maxRequiredMarginPct;   // Default 20%
   double   m_minFreeMarginPct;       // Default 50%
   double   m_minMarginLevelPct;      // Default 300%
   double   m_extraCommissionPerLot;  // Estimated round-trip commission in money
   double   m_expectedSlippagePoints; // Estimated slippage buffer
   double   m_maxRiskMoney;           // Maximum Dollar Risk per trade (Default $50)
   
   // Cached Symbol properties
   double   m_point;
   int      m_digits;
   double   m_tickSize;
   double   m_tickValue;
   double   m_contractSize;
   double   m_volumeMin;
   double   m_volumeStep;
   double   m_volumeMax;
   int      m_stopsLevel;
   int      m_freezeLevel;

public:
   CPositionSizingModule() :
      m_symbol(""),
      m_riskPercent(0.25),
      m_tpMultiplier(1.8),
      m_maxRequiredMarginPct(20.0),
      m_minFreeMarginPct(50.0),
      m_minMarginLevelPct(300.0),
      m_extraCommissionPerLot(0.0),
      m_expectedSlippagePoints(2.0),
      m_maxRiskMoney(50.0),
      m_point(0.00001),
      m_digits(5),
      m_tickSize(0.00001),
      m_tickValue(1.0),
      m_contractSize(100000.0),
      m_volumeMin(0.01),
      m_volumeStep(0.01),
      m_volumeMax(100.0),
      m_stopsLevel(0),
      m_freezeLevel(0)
   {}
   
   bool Init(string symbol, double riskPct = 0.25, double tpMult = 1.8, 
             double maxMargin = 20.0, double minFreeMargin = 50.0, double minMarginLevel = 300.0,
             double commPerLot = 0.0, double slippagePts = 2.0, double maxRiskMoney = 50.0)
   {
      m_symbol = symbol;
      m_riskPercent = (riskPct > 0.0) ? riskPct : 0.25;
      m_tpMultiplier = (tpMult > 0.0) ? tpMult : 1.8;
      m_maxRequiredMarginPct = maxMargin;
      m_minFreeMarginPct = minFreeMargin;
      m_minMarginLevelPct = minMarginLevel;
      m_extraCommissionPerLot = commPerLot;
      m_expectedSlippagePoints = slippagePts;
      m_maxRiskMoney = (maxRiskMoney > 0.0) ? maxRiskMoney : 50.0;
      
      return RefreshSymbolInfo();
   }
   
   bool RefreshSymbolInfo()
   {
      ResetLastError();
      m_point        = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits       = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_tickSize     = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_volumeMin    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_volumeStep   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_volumeMax    = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_stopsLevel   = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      
      if(m_tickSize <= 0.0 || m_volumeStep <= 0.0 || m_contractSize <= 0.0)
      {
         PrintFormat("[PositionSizing] Error fetching symbol specifications for %s (Error %d)", m_symbol, GetLastError());
         return false;
      }
      return true;
   }
   
   // Normalizes price preserving directional risk
   // Long SL: round down (floor)
   // Short SL: round up (ceil)
   // Long TP: round up (ceil)
   // Short TP: round down (floor)
   double NormalizeDirectionalPrice(double price, bool roundUp)
   {
      if(m_tickSize <= 0.0) return price;
      
      double steps = price / m_tickSize;
      double normalizedSteps;
      
      if(roundUp)
         normalizedSteps = MathCeil(steps - 1e-9);
      else
         normalizedSteps = MathFloor(steps + 1e-9);
         
      return NormalizeDouble(normalizedSteps * m_tickSize, m_digits);
   }
   
   // Calculates SL, TP, and stop distances for Long or Short
   bool CalculateStops(bool isLong, double entryPrice, double swingLevel, double currentATR,
                       double &stopLoss, double &takeProfit, double &stopDistance, string &reason)
   {
      RefreshSymbolInfo();
      
      if(currentATR <= 0.0)
      {
         reason = "CurrentATR is zero or negative";
         return false;
      }
      
      double structureStop = 0.0;
      double atrStop = 0.0;
      double rawStop = 0.0;
      
      if(isLong)
      {
         structureStop = swingLevel - (0.10 * currentATR);
         atrStop = entryPrice - (1.80 * currentATR);
         // If structure stop is too wide (> 2.5 ATR), cap at 2.0 ATR
         if((entryPrice - structureStop) > 2.5 * currentATR)
            rawStop = entryPrice - (2.0 * currentATR);
         else
            rawStop = MathMin(structureStop, atrStop);
         stopLoss = NormalizeDirectionalPrice(rawStop, false);
         stopDistance = entryPrice - stopLoss;
      }
      else // Short
      {
         structureStop = swingLevel + (0.10 * currentATR);
         atrStop = entryPrice + (1.80 * currentATR);
         // If structure stop is too wide (> 2.5 ATR), cap at 2.0 ATR
         if((structureStop - entryPrice) > 2.5 * currentATR)
            rawStop = entryPrice + (2.0 * currentATR);
         else
            rawStop = MathMax(structureStop, atrStop);
         stopLoss = NormalizeDirectionalPrice(rawStop, true);
         stopDistance = stopLoss - entryPrice;
      }
      
      // Stop distance bounds check: 0 < stopDistance <= 2.5 * CurrentATR
      if(stopDistance <= 0.0)
      {
         reason = StringFormat("Invalid stop distance (%.5f <= 0)", stopDistance);
         return false;
      }
      
      if(stopDistance > 2.5 * currentATR)
      {
         reason = StringFormat("Stop distance exceeds 2.5 * ATR (%.5f > %.5f)", stopDistance, 2.5 * currentATR);
         return false;
      }
      
      // Calculate Take-Profit target: Default 1.8R
      double targetDistance = m_tpMultiplier * stopDistance;
      double rawTP = 0.0;
      
      if(isLong)
      {
         rawTP = entryPrice + targetDistance;
         takeProfit = NormalizeDirectionalPrice(rawTP, true); // Round up
      }
      else
      {
         rawTP = entryPrice - targetDistance;
         takeProfit = NormalizeDirectionalPrice(rawTP, false); // Round down
      }
      
      // Stop and Freeze level check against current executable prices (Bid for Long, Ask for Sell)
      MqlTick tick;
      if(SymbolInfoTick(m_symbol, tick))
      {
         double minExecutableStopDist = MathMax(m_stopsLevel, m_freezeLevel) * m_point;
         if(isLong)
         {
            if((tick.bid - stopLoss) < minExecutableStopDist)
            {
               reason = StringFormat("Long SL too close to current Bid (Bid %.5f - SL %.5f = %.5f < min %.5f)",
                                     tick.bid, stopLoss, tick.bid - stopLoss, minExecutableStopDist);
               return false;
            }
            if((takeProfit - tick.bid) < minExecutableStopDist)
            {
               reason = StringFormat("Long TP too close to current Bid (TP %.5f - Bid %.5f = %.5f < min %.5f)",
                                     takeProfit, tick.bid, takeProfit - tick.bid, minExecutableStopDist);
               return false;
            }
         }
         else
         {
            if((stopLoss - tick.ask) < minExecutableStopDist)
            {
               reason = StringFormat("Short SL too close to current Ask (SL %.5f - Ask %.5f = %.5f < min %.5f)",
                                     stopLoss, tick.ask, stopLoss - tick.ask, minExecutableStopDist);
               return false;
            }
            if((tick.ask - takeProfit) < minExecutableStopDist)
            {
               reason = StringFormat("Short TP too close to current Ask (Ask %.5f - TP %.5f = %.5f < min %.5f)",
                                     tick.ask, takeProfit, tick.ask - takeProfit, minExecutableStopDist);
               return false;
            }
         }
      }
      else
      {
         // Fallback to entryPrice if tick unavailable
         double minBrokerStopDist = MathMax(m_stopsLevel, m_freezeLevel) * m_point;
         if(stopDistance < minBrokerStopDist)
         {
            reason = StringFormat("Stop distance below broker stops level (%.5f < %.5f)", stopDistance, minBrokerStopDist);
            return false;
         }
      }
      
      reason = "";
      return true;
   }
   
   // Calculates Volume using OrderCalcProfit with adverse fill price and strict downward step rounding
   bool CalculateVolume(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLoss,
                        double &rawVolume, double &finalVolume, double &riskMoney, string &reason)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
      {
         reason = "Account equity is zero or negative";
         return false;
      }
      
      riskMoney = equity * (m_riskPercent / 100.0);
      if(m_maxRiskMoney > 0.0)
      {
         riskMoney = MathMin(m_maxRiskMoney, riskMoney);
      }
      
      // Calculate loss of 1.0 lot between adverse entry price and SL using broker engine
      // This properly accounts for symbol-specific contract sizing, tick size, and tick value
      double adverseEntry = entryPrice;
      if(m_expectedSlippagePoints > 0.0)
      {
         if(orderType == ORDER_TYPE_BUY)
            adverseEntry = entryPrice + (m_expectedSlippagePoints * m_point);
         else if(orderType == ORDER_TYPE_SELL)
            adverseEntry = entryPrice - (m_expectedSlippagePoints * m_point);
      }
      
      double oneLotProfit = 0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType, m_symbol, 1.0, adverseEntry, stopLoss, oneLotProfit))
      {
         // Fallback to unadjusted entryPrice if adverse calculation fails
         if(!OrderCalcProfit(orderType, m_symbol, 1.0, entryPrice, stopLoss, oneLotProfit))
         {
            reason = StringFormat("OrderCalcProfit failed for 1.0 lot (Error %d)", GetLastError());
            return false;
         }
      }
      
      double oneLotLoss = MathAbs(oneLotProfit) + m_extraCommissionPerLot;
      
      if(oneLotLoss <= 0.0)
      {
         reason = "Calculated 1-lot loss is zero or invalid";
         return false;
      }
      
      if(oneLotLoss <= 0.0)
      {
         reason = "Calculated 1-lot loss is zero or invalid";
         return false;
      }
      
      // Raw unrounded volume
      rawVolume = riskMoney / oneLotLoss;
      
      // STRICT downward rounding to volume step
      double steps = MathFloor((rawVolume - m_volumeMin) / m_volumeStep);
      finalVolume = m_volumeMin + (steps * m_volumeStep);
      
      // Determine volume decimal digits
      int volDigits = 0;
      if(m_volumeStep < 0.1) volDigits = 2;
      else if(m_volumeStep < 1.0) volDigits = 1;
      finalVolume = NormalizeDouble(finalVolume, volDigits);
      
      // Check broker minimum volume: allow minimum volume if actual dollar risk is within InpMaxRiskMoney
      if(rawVolume < m_volumeMin)
      {
         double minLotLoss = 0.0;
         if(!OrderCalcProfit(orderType, m_symbol, m_volumeMin, entryPrice, stopLoss, minLotLoss))
            minLotLoss = 0.0;
         
         double absMinLotLoss = MathAbs(minLotLoss) + m_extraCommissionPerLot;
         if(m_maxRiskMoney > 0.0 && absMinLotLoss <= (m_maxRiskMoney * 1.05))
         {
            finalVolume = m_volumeMin;
         }
         else
         {
            reason = StringFormat("Raw volume (%.4f) below broker minimum (%.2f). Min volume risk $%.2f exceeds risk budget $%.2f", 
                                  rawVolume, m_volumeMin, absMinLotLoss, riskMoney);
            return false;
         }
      }
      
      if(finalVolume < m_volumeMin)
      {
         reason = StringFormat("Final volume (%.2f) below broker minimum (%.2f)", finalVolume, m_volumeMin);
         return false;
      }
      
      if(finalVolume > m_volumeMax)
      {
         finalVolume = m_volumeMax;
      }
      
      // Recalculate final risk with normalized volume
      double actualProfit = 0.0;
      if(!OrderCalcProfit(orderType, m_symbol, finalVolume, entryPrice, stopLoss, actualProfit))
      {
         reason = "Failed to calculate profit for normalized volume";
         return false;
      }
      double finalRiskMoney = MathAbs(actualProfit) + (m_extraCommissionPerLot * finalVolume);
      
      // Reject if final risk exceeds risk budget by more than 1% tolerance (unless allowed under min volume within max risk money)
      if(finalRiskMoney > (riskMoney * 1.01))
      {
         if(finalVolume == m_volumeMin && m_maxRiskMoney > 0.0 && finalRiskMoney <= (m_maxRiskMoney * 1.05))
         {
            // Allowed under small account minimum volume exception capped by InpMaxRiskMoney
         }
         else
         {
            reason = StringFormat("Normalized risk $%.2f exceeds risk budget $%.2f", finalRiskMoney, riskMoney);
            return false;
         }
      }
      
      reason = "";
      return true;
   }
   
   // Validates margin limits before entry
   bool CheckMargin(ENUM_ORDER_TYPE orderType, double volume, double entryPrice,
                    double &requiredMargin, string &reason)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double currentMargin = AccountInfoDouble(ACCOUNT_MARGIN);
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      
      ResetLastError();
      if(!OrderCalcMargin(orderType, m_symbol, volume, entryPrice, requiredMargin))
      {
         reason = StringFormat("OrderCalcMargin failed for volume %.2f (Error %d)", volume, GetLastError());
         return false;
      }
      
      // 1. Max required margin <= 20% of equity
      double maxAllowedMargin = equity * (m_maxRequiredMarginPct / 100.0);
      if(requiredMargin > maxAllowedMargin)
      {
         reason = StringFormat("Required margin $%.2f exceeds %.0f%% of equity ($%.2f)", 
                               requiredMargin, m_maxRequiredMarginPct, maxAllowedMargin);
         return false;
      }
      
      // 2. Minimum post-trade free margin >= 50% of equity
      double postFreeMargin = freeMargin - requiredMargin;
      double minFreeMarginAllowed = equity * (m_minFreeMarginPct / 100.0);
      if(postFreeMargin < minFreeMarginAllowed)
      {
         reason = StringFormat("Post-trade free margin $%.2f below %.0f%% of equity ($%.2f)", 
                               postFreeMargin, m_minFreeMarginPct, minFreeMarginAllowed);
         return false;
      }
      
      // 3. Minimum post-trade margin level >= 300%
      double totalNewMargin = currentMargin + requiredMargin;
      if(totalNewMargin > 0)
      {
         double postMarginLevel = (equity / totalNewMargin) * 100.0;
         if(postMarginLevel < m_minMarginLevelPct)
         {
            reason = StringFormat("Post-trade margin level %.1f%% below minimum %.0f%%", 
                                  postMarginLevel, m_minMarginLevelPct);
            return false;
         }
      }
      
      reason = "";
      return true;
   }
   
   // Getters
   double GetRiskPercent()     { return m_riskPercent; }
   double GetVolumeMin()       { return m_volumeMin; }
   double GetVolumeStep()      { return m_volumeStep; }
   double GetTickSize()        { return m_tickSize; }
   double GetPoint()           { return m_point; }
   int    GetDigits()          { return m_digits; }
};
