//+------------------------------------------------------------------+
//|                                        MarketStructureModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| CMarketStructureModule Class                                     |
//+------------------------------------------------------------------+
class CMarketStructureModule
{
private:
   string m_symbol;

public:
   CMarketStructureModule() : m_symbol("") {}
   
   void Init(string symbol)
   {
      m_symbol = symbol;
   }
   
   // Finds Lowest Low of M15 bars between shiftStart and shiftEnd (inclusive)
   // For task: shifts 1 through 5
   bool GetLowestLow(int shiftStart, int shiftEnd, double &lowestLow)
   {
      lowestLow = DBL_MAX;
      int count = shiftEnd - shiftStart + 1;
      if(count <= 0) return false;
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, shiftStart, count, rates);
      if(copied < count)
      {
         PrintFormat("[MarketStructure] Failed to copy rates for LowestLow (requested %d, got %d)", count, copied);
         return false;
      }
      
      for(int i = 0; i < count; i++)
      {
         if(rates[i].low < lowestLow)
            lowestLow = rates[i].low;
      }
      return true;
   }
   
   // Finds Highest High of M15 bars between shiftStart and shiftEnd (inclusive)
   // For task: shifts 1 through 5
   bool GetHighestHigh(int shiftStart, int shiftEnd, double &highestHigh)
   {
      highestHigh = -DBL_MAX;
      int count = shiftEnd - shiftStart + 1;
      if(count <= 0) return false;
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, shiftStart, count, rates);
      if(copied < count)
      {
         PrintFormat("[MarketStructure] Failed to copy rates for HighestHigh (requested %d, got %d)", count, copied);
         return false;
      }
      
      for(int i = 0; i < count; i++)
      {
         if(rates[i].high > highestHigh)
            highestHigh = rates[i].high;
      }
      return true;
   }
   
   // Checks if at least one candle in shifts 2 through (1 + lookbackBars) entered the M15 EMA20 pullback zone
   // Long pullback zone: Low <= EMA20 + zoneTolerance * ATR and Close >= EMA20 - 0.50 * ATR
   // Short pullback zone: High >= EMA20 - zoneTolerance * ATR and Close <= EMA20 + 0.50 * ATR
   // Optional rejection requirement: candle closes in direction of trend or in upper/lower 40% of range
   bool CheckPullback(bool isLong, const double &ema20Buffer[], double currentATR,
                      int lookbackBars, double zoneToleranceATR, bool requireRejection, string &reason)
   {
      if(lookbackBars < 2) lookbackBars = 3;
      if(lookbackBars > 10) lookbackBars = 10;
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      // Copy shifts 2 through (1 + lookbackBars)
      int copied = CopyRates(m_symbol, PERIOD_M15, 2, lookbackBars, rates);
      if(copied < lookbackBars)
      {
         reason = "Failed to copy M15 rates for pullback check";
         return false;
      }
      
      bool inPullbackZone = false;
      bool rejectionConfirmed = false;
      
      for(int i = 0; i < lookbackBars; i++)
      {
         int shift = i + 2;
         double ema = ema20Buffer[shift];
         if(ema == 0.0 || ema == EMPTY_VALUE)
         {
            reason = "Invalid EMA20 value at shift " + IntegerToString(shift);
            return false;
         }
         
         double candleRange = rates[i].high - rates[i].low;
         
         if(isLong)
         {
            // Pullback zone check
            double upperLimit = ema + (zoneToleranceATR * currentATR);
            double lowerLimit = ema - (0.50 * currentATR);
            if(rates[i].low <= upperLimit && rates[i].close >= lowerLimit)
            {
               inPullbackZone = true;
               
               // Rejection / resumption check
               if(!requireRejection)
               {
                  rejectionConfirmed = true;
                  break;
               }
               
               double clv = (candleRange > 0.0) ? (rates[i].close - rates[i].low) / candleRange : 0.0;
               if(rates[i].close >= rates[i].open || clv >= 0.60)
               {
                  rejectionConfirmed = true;
                  break;
               }
            }
         }
         else // Short
         {
            // Pullback zone check
            double lowerLimit = ema - (zoneToleranceATR * currentATR);
            double upperLimit = ema + (0.50 * currentATR);
            if(rates[i].high >= lowerLimit && rates[i].close <= upperLimit)
            {
               inPullbackZone = true;
               
               // Rejection / resumption check
               if(!requireRejection)
               {
                  rejectionConfirmed = true;
                  break;
               }
               
               double clv = (candleRange > 0.0) ? (rates[i].high - rates[i].close) / candleRange : 0.0;
               if(rates[i].close <= rates[i].open || clv >= 0.60)
               {
                  rejectionConfirmed = true;
                  break;
               }
            }
         }
      }
      
      if(!inPullbackZone)
      {
         reason = isLong ? StringFormat("No M15 candle in shifts 2-%d entered EMA20 pullback zone (+%.2f ATR / -0.50 ATR)", 
                                        lookbackBars + 1, zoneToleranceATR) :
                           StringFormat("No M15 candle in shifts 2-%d entered EMA20 pullback zone (-%.2f ATR / +0.50 ATR)", 
                                        lookbackBars + 1, zoneToleranceATR);
         return false;
      }
      
      if(requireRejection && !rejectionConfirmed)
      {
         reason = isLong ? "Pullback entered zone but lacked bullish rejection / resumption candle" :
                           "Pullback entered zone but lacked bearish rejection / resumption candle";
         return false;
      }
      
      reason = "";
      return true;
   }
   
   // Breakout confirmation on shift 1 with breakout distance and candle quality checks
   // Long: Close[1] > High[2], Close[1] > EMA20[1], BreakoutDistance >= minBreakoutDistATR * ATR
   // Short: Close[1] < Low[2], Close[1] < EMA20[1], BreakoutDistance >= minBreakoutDistATR * ATR
   bool CheckBreakout(bool isLong, double close1, double ema20_1, double currentATR,
                      double minBreakoutDistATR, string &reason)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      // Copy shifts 1 and 2 (indices: 0 = shift 1, 1 = shift 2)
      int copied = CopyRates(m_symbol, PERIOD_M15, 1, 2, rates);
      if(copied < 2)
      {
         reason = "Failed to copy M15 shift 1 & 2 rates for breakout confirmation";
         return false;
      }
      
      double shift2High = rates[1].high;
      double shift2Low  = rates[1].low;
      double candle1Range = rates[0].high - rates[0].low;
      
      if(isLong)
      {
         if(close1 <= shift2High)
         {
            reason = StringFormat("Close[1] (%.5f) did not close above High[2] (%.5f)", close1, shift2High);
            return false;
         }
         if(close1 <= ema20_1)
         {
            reason = StringFormat("Close[1] (%.5f) did not close above EMA20[1] (%.5f)", close1, ema20_1);
            return false;
         }
         
         double breakoutDistance = close1 - shift2High;
         double minDistance = minBreakoutDistATR * currentATR;
         if(breakoutDistance < minDistance)
         {
            reason = StringFormat("Breakout distance too weak: %.5f < %.2f * ATR (%.5f)", 
                                  breakoutDistance, minBreakoutDistATR, minDistance);
            return false;
         }
         
         // Close location value check (candle closes in upper 50% of its range)
         if(candle1Range > 0.0)
         {
            double clv = (close1 - rates[0].low) / candle1Range;
            if(clv < 0.50)
            {
               reason = StringFormat("Breakout candle closed in lower half of range (CLV: %.2f < 0.50)", clv);
               return false;
            }
         }
      }
      else // Short
      {
         if(close1 >= shift2Low)
         {
            reason = StringFormat("Close[1] (%.5f) did not close below Low[2] (%.5f)", close1, shift2Low);
            return false;
         }
         if(close1 >= ema20_1)
         {
            reason = StringFormat("Close[1] (%.5f) did not close below EMA20[1] (%.5f)", close1, ema20_1);
            return false;
         }
         
         double breakoutDistance = shift2Low - close1;
         double minDistance = minBreakoutDistATR * currentATR;
         if(breakoutDistance < minDistance)
         {
            reason = StringFormat("Breakout distance too weak: %.5f < %.2f * ATR (%.5f)", 
                                  breakoutDistance, minBreakoutDistATR, minDistance);
            return false;
         }
         
         // Close location value check (candle closes in lower 50% of its range)
         if(candle1Range > 0.0)
         {
            double clv = (rates[0].high - close1) / candle1Range;
            if(clv < 0.50)
            {
               reason = StringFormat("Breakout candle closed in upper half of range (CLV: %.2f < 0.50)", clv);
               return false;
            }
         }
      }
      
      reason = "";
      return true;
   }
   
   // Breakout-Retest Entry Model (SETUP_BREAKOUT_RETEST)
   // Captures high-quality retests after an initial breakout
   bool CheckBreakoutRetest(bool isLong, double close1, double ema20_1, double currentATR,
                            double &breakoutLevel, string &reason)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      // Copy shifts 1 through 4 (0=shift 1 retest, 1=shift 2 breakout, 2=shift 3 level, 3=shift 4)
      int copied = CopyRates(m_symbol, PERIOD_M15, 1, 4, rates);
      if(copied < 4)
      {
         reason = "Failed to copy M15 rates for breakout-retest check";
         return false;
      }
      
      double tolerance = 0.15 * currentATR;
      
      if(isLong)
      {
         double level = MathMax(rates[2].high, rates[3].high);
         bool brokeAbove = (rates[1].close > level);
         if(!brokeAbove)
         {
            reason = "No confirmed prior breakout above resistance level for retest";
            return false;
         }
         
         // Shift 1 retested the broken resistance level and held
         bool retested = (rates[0].low <= (level + tolerance) && rates[0].close > level);
         if(!retested)
         {
            reason = StringFormat("Shift 1 did not retest level %.5f with rejection", level);
            return false;
         }
         
         double range1 = rates[0].high - rates[0].low;
         double clv = (range1 > 0.0) ? (rates[0].close - rates[0].low) / range1 : 0.0;
         if(rates[0].close < rates[0].open && clv < 0.60)
         {
            reason = "Retest candle closed bearish without bullish rejection";
            return false;
         }
         
         breakoutLevel = level;
      }
      else // Short
      {
         double level = MathMin(rates[2].low, rates[3].low);
         bool brokeBelow = (rates[1].close < level);
         if(!brokeBelow)
         {
            reason = "No confirmed prior breakout below support level for retest";
            return false;
         }
         
         // Shift 1 retested the broken support level and held
         bool retested = (rates[0].high >= (level - tolerance) && rates[0].close < level);
         if(!retested)
         {
            reason = StringFormat("Shift 1 did not retest level %.5f with rejection", level);
            return false;
         }
         
         double range1 = rates[0].high - rates[0].low;
         double clv = (range1 > 0.0) ? (rates[0].high - rates[0].close) / range1 : 0.0;
         if(rates[0].close > rates[0].open && clv < 0.60)
         {
            reason = "Retest candle closed bullish without bearish rejection";
            return false;
         }
         
         breakoutLevel = level;
      }
      
      reason = "";
      return true;
   }
};
