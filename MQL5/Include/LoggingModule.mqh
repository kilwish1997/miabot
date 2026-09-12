//+------------------------------------------------------------------+
//|                                                LoggingModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Structure to capture evaluation and filter details
struct EvaluationLogRecord
{
   datetime    timestamp;
   datetime    brokerServerTime;
   datetime    utcTime;
   string      accountMasked;
   string      symbol;
   ulong       magic;
   datetime    signalBarTime;
   string      direction;
   double      h1EMA50;
   double      h1EMA200;
   double      h1ADX;
   double      m15EMA20;
   double      m15ATR;
   double      medianATR;
   double      spread;
   double      signalClose;
   double      entryPrice;
   double      stopLoss;
   double      takeProfit;
   double      stopDistance;
   double      riskPercentage;
   double      riskMoney;
   double      rawVolume;
   double      finalVolume;
   double      minVolume;
   double      volumeStep;
   double      estimatedMargin;
   string      dailyLossStatus;
   string      weeklyLossStatus;
   string      drawdownStatus;
   string      newsStatus;
   string      sessionStatus;
   
   // Booleans
   bool        connectionOK;
   bool        dataOK;
   bool        sessionOK;
   bool        exposureOK;
   bool        dailyLossOK;
   bool        weeklyLossOK;
   bool        drawdownOK;
   bool        newsOK;
   bool        trendOK;
   bool        pullbackOK;
   bool        breakoutOK;
   bool        volatilityOK;
   bool        spreadOK;
   bool        priceDistanceOK;
   bool        stopOK;
   bool        riskOK;
   bool        volumeOK;
   bool        marginOK;
   bool        orderCheckOK;
   
   string      rejectionReason;
   string      orderRequestResult;
   uint        tradeServerRetcode;
   ulong       dealTicket;
   ulong       positionTicket;
   double      actualEntryPrice;
   double      actualSpread;
   double      estimatedSlippage;
   double      exitPrice;
   string      exitReason;
   double      resultMoney;
   double      resultR;
};

//+------------------------------------------------------------------+
//| CLoggingModule Class                                            |
//+------------------------------------------------------------------+
class CLoggingModule
{
private:
   int         m_fileHandle;
   string      m_fileName;
   string      m_symbol;
   ulong       m_magic;
   bool        m_initialized;
   
   // Rejection Funnel Counters
   int         m_evalCount;
   int         m_tradesPlaced;
   int         m_rejectConnection;
   int         m_rejectData;
   int         m_rejectSession;
   int         m_rejectExposure;
   int         m_rejectDailyLoss;
   int         m_rejectWeeklyLoss;
   int         m_rejectDrawdown;
   int         m_rejectNews;
   int         m_rejectVolatility;
   int         m_rejectTrend;
   int         m_rejectPullback;
   int         m_rejectBreakout;
   int         m_rejectPriceDrift;
   int         m_rejectStopLoss;
   int         m_rejectSpread;
   int         m_rejectVolume;
   int         m_rejectMargin;
   int         m_rejectOrderCheck;
   
   string MaskAccountNumber(long accNum)
   {
      string s = IntegerToString(accNum);
      int len = StringLen(s);
      if(len <= 3) return "***";
      return StringSubstr(s, 0, 2) + "****" + StringSubstr(s, len - 2);
   }

   string BoolToString(bool val)
   {
      return val ? "TRUE" : "FALSE";
   }

   string EscapeCsv(string text)
   {
      StringReplace(text, "\"", "\"\"");
      return "\"" + text + "\"";
   }

   void WriteHeader()
   {
      if(m_fileHandle == INVALID_HANDLE) return;
      
      string header = "Timestamp,BrokerServerTime,UTCTime,AccountMasked,Symbol,Magic,"
                      "SignalBarTime,Direction,H1_EMA50,H1_EMA200,H1_ADX,M15_EMA20,"
                      "M15_ATR,Median_ATR,Spread,SignalClose,EntryPrice,StopLoss,"
                      "TakeProfit,StopDistance,RiskPercentage,RiskMoney,RawVolume,"
                      "FinalVolume,MinVolume,VolumeStep,EstimatedMargin,DailyLossStatus,"
                      "WeeklyLossStatus,DrawdownStatus,NewsStatus,SessionStatus,"
                      "ConnectionOK,DataOK,SessionOK,ExposureOK,DailyLossOK,WeeklyLossOK,"
                      "DrawdownOK,NewsOK,TrendOK,PullbackOK,BreakoutOK,VolatilityOK,"
                      "SpreadOK,PriceDistanceOK,StopOK,RiskOK,VolumeOK,MarginOK,OrderCheckOK,"
                      "RejectionReason,OrderRequestResult,TradeServerRetcode,DealTicket,"
                      "PositionTicket,ActualEntryPrice,ActualSpread,EstimatedSlippage,"
                      "ExitPrice,ExitReason,ResultMoney,ResultR\r\n";
                      
      FileWriteString(m_fileHandle, header);
      FileFlush(m_fileHandle);
   }

   void ResetCounters()
   {
      m_evalCount        = 0;
      m_tradesPlaced     = 0;
      m_rejectConnection = 0;
      m_rejectData       = 0;
      m_rejectSession    = 0;
      m_rejectExposure   = 0;
      m_rejectDailyLoss  = 0;
      m_rejectWeeklyLoss = 0;
      m_rejectDrawdown   = 0;
      m_rejectNews       = 0;
      m_rejectVolatility = 0;
      m_rejectTrend      = 0;
      m_rejectPullback   = 0;
      m_rejectBreakout   = 0;
      m_rejectPriceDrift = 0;
      m_rejectStopLoss   = 0;
      m_rejectSpread     = 0;
      m_rejectVolume     = 0;
      m_rejectMargin     = 0;
      m_rejectOrderCheck = 0;
   }

public:
   CLoggingModule() : 
      m_fileHandle(INVALID_HANDLE), 
      m_initialized(false), 
      m_symbol(""),
      m_magic(0)
   {
      ResetCounters();
   }
   
   ~CLoggingModule() { Close(); }

   bool Init(string symbol, ulong magic)
   {
      m_symbol = symbol;
      m_magic = magic;
      ResetCounters();
      
      m_fileName = "H1TrendM15PullbackBreakoutEA_" + m_symbol + "_" + IntegerToString(m_magic) + ".csv";
      
      // Open in local terminal data folder Files/
      m_fileHandle = FileOpen(m_fileName, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ, ',');
      if(m_fileHandle == INVALID_HANDLE)
      {
         PrintFormat("[LoggingModule] Error opening log file %s (Error %d)", m_fileName, GetLastError());
         return false;
      }
      
      // If new file, write header
      if(FileSize(m_fileHandle) == 0)
      {
         WriteHeader();
      }
      else
      {
         // Seek to the end for appending
         FileSeek(m_fileHandle, 0, SEEK_END);
      }
      
      m_initialized = true;
      PrintFormat("[LoggingModule] Initialized log file: MQL5/Files/%s", m_fileName);
      return true;
   }

   void Close()
   {
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileFlush(m_fileHandle);
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
      m_initialized = false;
   }

   void LogRecord(const EvaluationLogRecord &rec)
   {
      if(!m_initialized && m_fileHandle == INVALID_HANDLE)
      {
         if(!Init(m_symbol, m_magic)) return;
      }
      
      m_evalCount++;
      
      // Update rejection funnel statistics
      if(rec.dealTicket > 0 || (rec.orderCheckOK && StringFind(rec.orderRequestResult, "Simulated") >= 0))
         m_tradesPlaced++;
      else if(!rec.connectionOK)    m_rejectConnection++;
      else if(!rec.dataOK)          m_rejectData++;
      else if(!rec.sessionOK)       m_rejectSession++;
      else if(!rec.exposureOK)      m_rejectExposure++;
      else if(!rec.dailyLossOK)     m_rejectDailyLoss++;
      else if(!rec.weeklyLossOK)    m_rejectWeeklyLoss++;
      else if(!rec.drawdownOK)      m_rejectDrawdown++;
      else if(!rec.newsOK)          m_rejectNews++;
      else if(!rec.volatilityOK)    m_rejectVolatility++;
      else if(!rec.trendOK)         m_rejectTrend++;
      else if(!rec.pullbackOK)      m_rejectPullback++;
      else if(!rec.breakoutOK)      m_rejectBreakout++;
      else if(!rec.priceDistanceOK) m_rejectPriceDrift++;
      else if(!rec.stopOK)          m_rejectStopLoss++;
      else if(!rec.spreadOK)        m_rejectSpread++;
      else if(!rec.riskOK || !rec.volumeOK) m_rejectVolume++;
      else if(!rec.marginOK)        m_rejectMargin++;
      else if(!rec.orderCheckOK)    m_rejectOrderCheck++;
      
      string line = "";
      line += TimeToString(rec.timestamp, TIME_DATE | TIME_SECONDS) + ",";
      line += TimeToString(rec.brokerServerTime, TIME_DATE | TIME_SECONDS) + ",";
      line += (rec.utcTime > 0 ? TimeToString(rec.utcTime, TIME_DATE | TIME_SECONDS) : "N/A") + ",";
      line += EscapeCsv(rec.accountMasked) + ",";
      line += rec.symbol + ",";
      line += IntegerToString(rec.magic) + ",";
      line += (rec.signalBarTime > 0 ? TimeToString(rec.signalBarTime, TIME_DATE | TIME_SECONDS) : "N/A") + ",";
      line += rec.direction + ",";
      line += DoubleToString(rec.h1EMA50, 5) + ",";
      line += DoubleToString(rec.h1EMA200, 5) + ",";
      line += DoubleToString(rec.h1ADX, 2) + ",";
      line += DoubleToString(rec.m15EMA20, 5) + ",";
      line += DoubleToString(rec.m15ATR, 5) + ",";
      line += DoubleToString(rec.medianATR, 5) + ",";
      line += DoubleToString(rec.spread, 5) + ",";
      line += DoubleToString(rec.signalClose, 5) + ",";
      line += DoubleToString(rec.entryPrice, 5) + ",";
      line += DoubleToString(rec.stopLoss, 5) + ",";
      line += DoubleToString(rec.takeProfit, 5) + ",";
      line += DoubleToString(rec.stopDistance, 5) + ",";
      line += DoubleToString(rec.riskPercentage, 2) + ",";
      line += DoubleToString(rec.riskMoney, 2) + ",";
      line += DoubleToString(rec.rawVolume, 2) + ",";
      line += DoubleToString(rec.finalVolume, 2) + ",";
      line += DoubleToString(rec.minVolume, 2) + ",";
      line += DoubleToString(rec.volumeStep, 2) + ",";
      line += DoubleToString(rec.estimatedMargin, 2) + ",";
      line += EscapeCsv(rec.dailyLossStatus) + ",";
      line += EscapeCsv(rec.weeklyLossStatus) + ",";
      line += EscapeCsv(rec.drawdownStatus) + ",";
      line += EscapeCsv(rec.newsStatus) + ",";
      line += EscapeCsv(rec.sessionStatus) + ",";
      
      // Booleans
      line += BoolToString(rec.connectionOK) + ",";
      line += BoolToString(rec.dataOK) + ",";
      line += BoolToString(rec.sessionOK) + ",";
      line += BoolToString(rec.exposureOK) + ",";
      line += BoolToString(rec.dailyLossOK) + ",";
      line += BoolToString(rec.weeklyLossOK) + ",";
      line += BoolToString(rec.drawdownOK) + ",";
      line += BoolToString(rec.newsOK) + ",";
      line += BoolToString(rec.trendOK) + ",";
      line += BoolToString(rec.pullbackOK) + ",";
      line += BoolToString(rec.breakoutOK) + ",";
      line += BoolToString(rec.volatilityOK) + ",";
      line += BoolToString(rec.spreadOK) + ",";
      line += BoolToString(rec.priceDistanceOK) + ",";
      line += BoolToString(rec.stopOK) + ",";
      line += BoolToString(rec.riskOK) + ",";
      line += BoolToString(rec.volumeOK) + ",";
      line += BoolToString(rec.marginOK) + ",";
      line += BoolToString(rec.orderCheckOK) + ",";
      
      line += EscapeCsv(rec.rejectionReason) + ",";
      line += EscapeCsv(rec.orderRequestResult) + ",";
      line += IntegerToString(rec.tradeServerRetcode) + ",";
      line += IntegerToString(rec.dealTicket) + ",";
      line += IntegerToString(rec.positionTicket) + ",";
      line += DoubleToString(rec.actualEntryPrice, 5) + ",";
      line += DoubleToString(rec.actualSpread, 5) + ",";
      line += DoubleToString(rec.estimatedSlippage, 5) + ",";
      line += DoubleToString(rec.exitPrice, 5) + ",";
      line += EscapeCsv(rec.exitReason) + ",";
      line += DoubleToString(rec.resultMoney, 2) + ",";
      line += DoubleToString(rec.resultR, 2) + "\r\n";
      
      FileWriteString(m_fileHandle, line);
      FileFlush(m_fileHandle);
   }

   // Prints full rejection funnel breakdown to log & writes summary file
   void PrintRejectionSummary()
   {
      if(m_evalCount == 0) return;
      
      double convRate = ((double)m_tradesPlaced / (double)m_evalCount) * 100.0;
      
      Print("==================================================================");
      PrintFormat("[REJECTION FUNNEL] Symbol: %s | Magic: %I64u | Total M15 Candles Evaluated: %d", m_symbol, m_magic, m_evalCount);
      PrintFormat("[REJECTION FUNNEL] Trades Placed: %d (Conversion: %.2f%%)", m_tradesPlaced, convRate);
      Print("------------------------------------------------------------------");
      PrintFormat("  - Filter: Outside Active Session / Rollover: %d (%.1f%%)", m_rejectSession, (m_rejectSession*100.0)/m_evalCount);
      PrintFormat("  - Filter: H1 Trend Alignment (EMA/ADX/DMI):  %d (%.1f%%)", m_rejectTrend, (m_rejectTrend*100.0)/m_evalCount);
      PrintFormat("  - Filter: M15 Pullback Zone / Rejection:     %d (%.1f%%)", m_rejectPullback, (m_rejectPullback*100.0)/m_evalCount);
      PrintFormat("  - Filter: M15 Breakout Quality / Distance:   %d (%.1f%%)", m_rejectBreakout, (m_rejectBreakout*100.0)/m_evalCount);
      PrintFormat("  - Filter: High-Impact News Blackout:         %d (%.1f%%)", m_rejectNews, (m_rejectNews*100.0)/m_evalCount);
      PrintFormat("  - Filter: ATR Volatility Threshold:          %d (%.1f%%)", m_rejectVolatility, (m_rejectVolatility*100.0)/m_evalCount);
      PrintFormat("  - Filter: Adverse Price Drift / Distance:    %d (%.1f%%)", m_rejectPriceDrift, (m_rejectPriceDrift*100.0)/m_evalCount);
      PrintFormat("  - Filter: Spread Buffer Exceeded:            %d (%.1f%%)", m_rejectSpread, (m_rejectSpread*100.0)/m_evalCount);
      PrintFormat("  - Filter: Existing Exposure Block:           %d (%.1f%%)", m_rejectExposure, (m_rejectExposure*100.0)/m_evalCount);
      PrintFormat("  - Filter: Daily/Weekly Loss / DD Limits:     %d (%.1f%%)", (m_rejectDailyLoss + m_rejectWeeklyLoss + m_rejectDrawdown), 
                  ((m_rejectDailyLoss + m_rejectWeeklyLoss + m_rejectDrawdown)*100.0)/m_evalCount);
      PrintFormat("  - Filter: Margin & Account Sizing Limits:    %d (%.1f%%)", (m_rejectVolume + m_rejectMargin + m_rejectOrderCheck),
                  ((m_rejectVolume + m_rejectMargin + m_rejectOrderCheck)*100.0)/m_evalCount);
      Print("==================================================================");
   }

   string GetMaskedAccount()
   {
      return MaskAccountNumber(AccountInfoInteger(ACCOUNT_LOGIN));
   }
};
