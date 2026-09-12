//+------------------------------------------------------------------+
//|                                                 SignalModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Structure to store all calculated indicator snapshots
struct IndicatorSnapshot
{
   double h1EMA50;
   double h1EMA50_prev;       // Shift 2 for slope evaluation
   double h1EMA200;
   double h1ADX;
   double h1PlusDI;           // +DI line
   double h1MinusDI;          // -DI line
   double h1Close1;
   
   double m15EMA20_1;
   double m15Close1;
   double currentATR;
   double medianATR;
};

//+------------------------------------------------------------------+
//| CSignalModule Class                                              |
//+------------------------------------------------------------------+
class CSignalModule
{
private:
   string   m_symbol;
   int      m_h1FastEMAPeriod;
   int      m_h1SlowEMAPeriod;
   int      m_h1ADXPeriod;
   double   m_minADX;
   int      m_m15EMAPeriod;
   int      m_m15ATRPeriod;
   int      m_atrLookbackBars;
   
   // Indicator handles
   int      m_handleH1EMA50;
   int      m_handleH1EMA200;
   int      m_handleH1ADX;
   int      m_handleM15EMA20;
   int      m_handleM15ATR;
   
   bool     m_initialized;

   // Helper for median calculation
   double CalculateMedian(double &arr[])
   {
      int size = ArraySize(arr);
      if(size <= 0) return 0.0;
      
      double sorted[];
      ArrayResize(sorted, size);
      ArrayCopy(sorted, arr);
      ArraySort(sorted);
      
      if(size % 2 == 1)
      {
         return sorted[size / 2];
      }
      else
      {
         return (sorted[size / 2 - 1] + sorted[size / 2]) / 2.0;
      }
   }

public:
   CSignalModule() :
      m_symbol(""),
      m_h1FastEMAPeriod(50),
      m_h1SlowEMAPeriod(200),
      m_h1ADXPeriod(14),
      m_minADX(20.0),
      m_m15EMAPeriod(20),
      m_m15ATRPeriod(14),
      m_atrLookbackBars(50),
      m_handleH1EMA50(INVALID_HANDLE),
      m_handleH1EMA200(INVALID_HANDLE),
      m_handleH1ADX(INVALID_HANDLE),
      m_handleM15EMA20(INVALID_HANDLE),
      m_handleM15ATR(INVALID_HANDLE),
      m_initialized(false)
   {}
   
   ~CSignalModule()
   {
      Release();
   }
   
   bool Init(string symbol, int h1Fast = 50, int h1Slow = 200, int h1ADX = 14, double minADX = 20.0,
             int m15EMA = 20, int m15ATR = 14, int atrLookback = 50)
   {
      m_symbol = symbol;
      m_h1FastEMAPeriod = h1Fast;
      m_h1SlowEMAPeriod = h1Slow;
      m_h1ADXPeriod = h1ADX;
      m_minADX = minADX;
      m_m15EMAPeriod = m15EMA;
      m_m15ATRPeriod = m15ATR;
      m_atrLookbackBars = atrLookback;
      
      Release(); // Clean any previous handles
      
      m_handleH1EMA50 = iMA(m_symbol, PERIOD_H1, m_h1FastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleH1EMA200 = iMA(m_symbol, PERIOD_H1, m_h1SlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleH1ADX = iADX(m_symbol, PERIOD_H1, m_h1ADXPeriod);
      m_handleM15EMA20 = iMA(m_symbol, PERIOD_M15, m_m15EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_handleM15ATR = iATR(m_symbol, PERIOD_M15, m_m15ATRPeriod);
      
      if(m_handleH1EMA50 == INVALID_HANDLE || m_handleH1EMA200 == INVALID_HANDLE ||
         m_handleH1ADX == INVALID_HANDLE || m_handleM15EMA20 == INVALID_HANDLE ||
         m_handleM15ATR == INVALID_HANDLE)
      {
         PrintFormat("[SignalModule] Error creating indicator handles! (Error: %d)", GetLastError());
         Release();
         return false;
      }
      
      m_initialized = true;
      return true;
   }
   
   void Release()
   {
      if(m_handleH1EMA50 != INVALID_HANDLE)  { IndicatorRelease(m_handleH1EMA50);  m_handleH1EMA50 = INVALID_HANDLE; }
      if(m_handleH1EMA200 != INVALID_HANDLE) { IndicatorRelease(m_handleH1EMA200); m_handleH1EMA200 = INVALID_HANDLE; }
      if(m_handleH1ADX != INVALID_HANDLE)    { IndicatorRelease(m_handleH1ADX);    m_handleH1ADX = INVALID_HANDLE; }
      if(m_handleM15EMA20 != INVALID_HANDLE) { IndicatorRelease(m_handleM15EMA20); m_handleM15EMA20 = INVALID_HANDLE; }
      if(m_handleM15ATR != INVALID_HANDLE)   { IndicatorRelease(m_handleM15ATR);   m_handleM15ATR = INVALID_HANDLE; }
      m_initialized = false;
   }
   
   // Copies M15 EMA20 series into buffer for pullback analysis (shifts 0 through 5)
   bool GetM15EMA20Buffer(double &buffer[], int count = 6)
   {
      ArraySetAsSeries(buffer, true);
      int copied = CopyBuffer(m_handleM15EMA20, 0, 0, count, buffer);
      return (copied >= count);
   }
   
   // Retrieves all indicator snapshots for the latest closed candles
   bool FetchSnapshot(IndicatorSnapshot &snap, string &reason)
   {
      if(!m_initialized)
      {
         reason = "Indicators not initialized";
         return false;
      }
      
      // 1. Copy H1 EMA 50 (shifts 1 and 2 for slope) & EMA 200 (shift 1)
      double h1FastBuf[], h1SlowBuf[];
      ArraySetAsSeries(h1FastBuf, true);
      ArraySetAsSeries(h1SlowBuf, true);
      if(CopyBuffer(m_handleH1EMA50, 0, 1, 2, h1FastBuf) < 2 ||
         CopyBuffer(m_handleH1EMA200, 0, 1, 1, h1SlowBuf) < 1)
      {
         reason = "Failed to copy H1 EMA buffers";
         return false;
      }
      snap.h1EMA50 = h1FastBuf[0];
      snap.h1EMA50_prev = h1FastBuf[1];
      snap.h1EMA200 = h1SlowBuf[0];
      
      // 2. Copy H1 ADX, +DI, and -DI (shift 1: buffer 0=MAIN, 1=PLUSDI, 2=MINUSDI)
      double h1ADXBuf[], h1PlusDIBuf[], h1MinusDIBuf[];
      ArraySetAsSeries(h1ADXBuf, true);
      ArraySetAsSeries(h1PlusDIBuf, true);
      ArraySetAsSeries(h1MinusDIBuf, true);
      if(CopyBuffer(m_handleH1ADX, 0, 1, 1, h1ADXBuf) < 1 ||
         CopyBuffer(m_handleH1ADX, 1, 1, 1, h1PlusDIBuf) < 1 ||
         CopyBuffer(m_handleH1ADX, 2, 1, 1, h1MinusDIBuf) < 1)
      {
         reason = "Failed to copy H1 ADX/DMI buffers";
         return false;
      }
      snap.h1ADX     = h1ADXBuf[0];
      snap.h1PlusDI  = h1PlusDIBuf[0];
      snap.h1MinusDI = h1MinusDIBuf[0];
      
      // 3. Copy H1 Close price of shift 1
      MqlRates h1Rates[];
      ArraySetAsSeries(h1Rates, true);
      if(CopyRates(m_symbol, PERIOD_H1, 1, 1, h1Rates) < 1)
      {
         reason = "Failed to copy H1 shift 1 rate";
         return false;
      }
      snap.h1Close1 = h1Rates[0].close;
      
      // 4. Copy M15 EMA 20 (shift 1)
      double m15EMABuf[];
      ArraySetAsSeries(m15EMABuf, true);
      if(CopyBuffer(m_handleM15EMA20, 0, 1, 1, m15EMABuf) < 1)
      {
         reason = "Failed to copy M15 EMA20 buffer";
         return false;
      }
      snap.m15EMA20_1 = m15EMABuf[0];
      
      // 5. Copy M15 Close price of shift 1
      MqlRates m15Rates[];
      ArraySetAsSeries(m15Rates, true);
      if(CopyRates(m_symbol, PERIOD_M15, 1, 1, m15Rates) < 1)
      {
         reason = "Failed to copy M15 shift 1 rate";
         return false;
      }
      snap.m15Close1 = m15Rates[0].close;
      
      // 6. Copy M15 CurrentATR (shift 1) and calculate MedianATR (shifts 2 to 51)
      int totalATRCount = 1 + m_atrLookbackBars;
      double m15ATRBuf[];
      ArraySetAsSeries(m15ATRBuf, true);
      int copiedATR = CopyBuffer(m_handleM15ATR, 0, 1, totalATRCount, m15ATRBuf);
      if(copiedATR < totalATRCount)
      {
         reason = StringFormat("Insufficient ATR historical bars (needed %d, got %d)", totalATRCount, copiedATR);
         return false;
      }
      
      snap.currentATR = m15ATRBuf[0]; // shift 1
      
      // Check finite & positive CurrentATR
      if(!MathIsValidNumber(snap.currentATR) || snap.currentATR <= 0.0)
      {
         reason = "CurrentATR is invalid, zero, or non-finite";
         return false;
      }
      
      // Build array of shifts 2..51
      double lookbackATRs[];
      ArrayResize(lookbackATRs, m_atrLookbackBars);
      for(int i = 0; i < m_atrLookbackBars; i++)
      {
         lookbackATRs[i] = m15ATRBuf[i + 1];
         if(!MathIsValidNumber(lookbackATRs[i]) || lookbackATRs[i] <= 0.0)
         {
            reason = "Lookback ATR history contains invalid or zero value";
            return false;
         }
      }
      
      snap.medianATR = CalculateMedian(lookbackATRs);
      if(!MathIsValidNumber(snap.medianATR) || snap.medianATR <= 0.0)
      {
         reason = "MedianATR calculation resulted in non-positive or invalid number";
         return false;
      }
      
      reason = "";
      return true;
   }
   
   // Validates H1 Trend Filter with optional Fast EMA slope and DMI direction confirmation
   // Long: FastEMA > SlowEMA, H1 Close[1] > FastEMA, FastEMA Slope >= 0, +DI > -DI, ADX14 >= minADX
   // Short: FastEMA < SlowEMA, H1 Close[1] < FastEMA, FastEMA Slope <= 0, -DI > +DI, ADX14 >= minADX
   bool CheckTrend(const IndicatorSnapshot &snap, int &trendDirection, 
                   bool requireSlope, bool requireDMI, string &reason)
   {
      trendDirection = 0; // 0 = None, 1 = Long, -1 = Short
      
      // Check Long
      if(snap.h1EMA50 > snap.h1EMA200 && snap.h1Close1 > snap.h1EMA50)
      {
         // Fast EMA slope check (shift 1 vs shift 2)
         if(requireSlope && snap.h1EMA50 < snap.h1EMA50_prev)
         {
            reason = StringFormat("Long trend rejected: H1 Fast EMA slope is negative (%.5f < %.5f)", 
                                  snap.h1EMA50, snap.h1EMA50_prev);
            return false;
         }
         
         // DMI dominance check (+DI must exceed -DI)
         if(requireDMI && snap.h1PlusDI <= snap.h1MinusDI)
         {
            reason = StringFormat("Long trend rejected: +DI (%.2f) <= -DI (%.2f)", 
                                  snap.h1PlusDI, snap.h1MinusDI);
            return false;
         }
         
         if(snap.h1ADX >= m_minADX)
         {
            trendDirection = 1;
            reason = "";
            return true;
         }
         else
         {
            reason = StringFormat("Long trend exists but H1 ADX (%.2f) < MinADX (%.2f)", snap.h1ADX, m_minADX);
            return false;
         }
      }
      
      // Check Short
      if(snap.h1EMA50 < snap.h1EMA200 && snap.h1Close1 < snap.h1EMA50)
      {
         // Fast EMA slope check (shift 1 vs shift 2)
         if(requireSlope && snap.h1EMA50 > snap.h1EMA50_prev)
         {
            reason = StringFormat("Short trend rejected: H1 Fast EMA slope is positive (%.5f > %.5f)", 
                                  snap.h1EMA50, snap.h1EMA50_prev);
            return false;
         }
         
         // DMI dominance check (-DI must exceed +DI)
         if(requireDMI && snap.h1MinusDI <= snap.h1PlusDI)
         {
            reason = StringFormat("Short trend rejected: -DI (%.2f) <= +DI (%.2f)", 
                                  snap.h1MinusDI, snap.h1PlusDI);
            return false;
         }
         
         if(snap.h1ADX >= m_minADX)
         {
            trendDirection = -1;
            reason = "";
            return true;
         }
         else
         {
            reason = StringFormat("Short trend exists but H1 ADX (%.2f) < MinADX (%.2f)", snap.h1ADX, m_minADX);
            return false;
         }
      }
      
      reason = "No valid H1 trend alignment (Fast EMA vs Slow EMA or Close vs Fast EMA)";
      return false;
   }
   
   // Validates Volatility Filter: 0.5 * MedianATR <= CurrentATR <= 2.0 * MedianATR
   bool CheckVolatility(const IndicatorSnapshot &snap, string &reason)
   {
      double minAllowed = 0.5 * snap.medianATR;
      double maxAllowed = 2.0 * snap.medianATR;
      
      if(snap.currentATR < minAllowed)
      {
         reason = StringFormat("Volatility too low: CurrentATR (%.5f) < 0.5 * MedianATR (%.5f)", 
                               snap.currentATR, minAllowed);
         return false;
      }
      
      if(snap.currentATR > maxAllowed)
      {
         reason = StringFormat("Volatility too high: CurrentATR (%.5f) > 2.0 * MedianATR (%.5f)", 
                               snap.currentATR, maxAllowed);
         return false;
      }
      
      reason = "";
      return true;
   }
};
