//+------------------------------------------------------------------+
//|                                              ExecutionModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| CExecutionModule Class                                           |
//+------------------------------------------------------------------+
class CExecutionModule
{
private:
   string   m_symbol;
   ulong    m_magic;
   ulong    m_maxDeviation;
   datetime m_lastProcessedBarTime; // Prevents duplicate orders for same M15 signal bar
   
   // Discovers broker filling mode
   ENUM_ORDER_TYPE_FILLING GetBestFillingMode()
   {
      uint fillingMode = (uint)SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE);
      
      // ORDER_FILLING_FOK = 1, ORDER_FILLING_IOC = 2, ORDER_FILLING_RETURN = 0
      if((fillingMode & SYMBOL_FILLING_FOK) != 0)
         return ORDER_FILLING_FOK;
      if((fillingMode & SYMBOL_FILLING_IOC) != 0)
         return ORDER_FILLING_IOC;
         
      return ORDER_FILLING_RETURN;
   }

public:
   CExecutionModule() :
      m_symbol(""),
      m_magic(0),
      m_maxDeviation(10),
      m_lastProcessedBarTime(0)
   {}
   
   void Init(string symbol, ulong magic, ulong deviation = 10)
   {
      m_symbol = symbol;
      m_magic = magic;
      m_maxDeviation = deviation;
      m_lastProcessedBarTime = 0;
   }
   
   // Prevents duplicate orders on the same completed M15 signal bar
   bool IsNewSignalBar(datetime signalBarTime)
   {
      if(signalBarTime <= m_lastProcessedBarTime)
         return false;
      return true;
   }
   
   void MarkBarProcessed(datetime signalBarTime)
   {
      m_lastProcessedBarTime = signalBarTime;
   }
   
   // Checks spread against Stop Distance (10%) and ATR (15%)
   bool CheckSpread(double currentATR, double stopDistance, double &actualSpread, string &reason)
   {
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
      {
         reason = "Symbol tick data unavailable for spread check";
         return false;
      }
      
      actualSpread = tick.ask - tick.bid;
      if(actualSpread <= 0.0)
      {
         reason = StringFormat("Invalid or negative spread (%.5f)", actualSpread);
         return false;
      }
      
      double maxSpreadStop = 0.10 * stopDistance;
      double maxSpreadATR  = 0.15 * currentATR;
      
      if(actualSpread > maxSpreadStop)
      {
         reason = StringFormat("Spread (%.5f) exceeds 10%% of stop distance (%.5f)", actualSpread, maxSpreadStop);
         return false;
      }
      
      if(actualSpread > maxSpreadATR)
      {
         reason = StringFormat("Spread (%.5f) exceeds 15%% of CurrentATR (%.5f)", actualSpread, maxSpreadATR);
         return false;
      }
      
      reason = "";
      return true;
   }
   
   // Checks asymmetric price drift from signal close:
   // Adverse drift <= maxAdverseDriftATR * ATR (default 0.20 ATR)
   // Total absolute distance <= maxTotalDistanceATR * ATR (default 0.40 ATR)
   bool CheckPriceDistance(bool isLong, double entryPrice, double signalClose, double currentATR, 
                           double &adverseDrift, double maxAdverseDriftATR, double maxTotalDistanceATR, 
                           string &reason)
   {
      // For Long: Ask > SignalClose is paying a worse/higher price
      // For Short: Bid < SignalClose is selling at a worse/lower price
      if(isLong)
         adverseDrift = entryPrice - signalClose;
      else
         adverseDrift = signalClose - entryPrice;
         
      double maxAdverse = maxAdverseDriftATR * currentATR;
      double maxTotal   = maxTotalDistanceATR * currentATR;
      double totalDist  = MathAbs(entryPrice - signalClose);
      
      if(adverseDrift > maxAdverse)
      {
         reason = StringFormat("Adverse price drift too high: %.5f > %.2f * ATR (%.5f)", 
                               adverseDrift, maxAdverseDriftATR, maxAdverse);
         return false;
      }
      
      if(totalDist > maxTotal)
      {
         reason = StringFormat("Total price drift from signal close too large: %.5f > %.2f * ATR (%.5f)", 
                               totalDist, maxTotalDistanceATR, maxTotal);
         return false;
      }
      
      reason = "";
      return true;
   }
   
   // Pre-flight check with OrderCheck() and executable stop level verification
   bool ValidateOrderCheck(ENUM_ORDER_TYPE orderType, double volume, double price, 
                           double sl, double tp, string &reason)
   {
      // 1. Validate stop distance against current executable prices and broker stop/freeze restrictions
      MqlTick tick;
      if(SymbolInfoTick(m_symbol, tick))
      {
         int stopsLevel  = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
         int freezeLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);
         double point    = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
         double minDist  = MathMax(stopsLevel, freezeLevel) * point;
         
         if(orderType == ORDER_TYPE_BUY)
         {
            if((tick.bid - sl) < minDist)
            {
               reason = StringFormat("Stop level check failed: Current Bid-SL (%.5f) < Min allowed (%.5f)", tick.bid - sl, minDist);
               return false;
            }
            if(tp > 0.0 && (tp - tick.bid) < minDist)
            {
               reason = StringFormat("Take profit check failed: Current TP-Bid (%.5f) < Min allowed (%.5f)", tp - tick.bid, minDist);
               return false;
            }
         }
         else if(orderType == ORDER_TYPE_SELL)
         {
            if((sl - tick.ask) < minDist)
            {
               reason = StringFormat("Stop level check failed: Current SL-Ask (%.5f) < Min allowed (%.5f)", sl - tick.ask, minDist);
               return false;
            }
            if(tp > 0.0 && (tick.ask - tp) < minDist)
            {
               reason = StringFormat("Take profit check failed: Current Ask-TP (%.5f) < Min allowed (%.5f)", tick.ask - tp, minDist);
               return false;
            }
         }
      }
      
      // 2. Broker OrderCheck() verification
      MqlTradeRequest request;
      MqlTradeCheckResult checkResult;
      ZeroMemory(request);
      ZeroMemory(checkResult);
      
      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = m_symbol;
      request.magic        = m_magic;
      request.volume       = volume;
      request.type         = orderType;
      request.price        = price;
      request.sl           = sl;
      request.tp           = tp;
      request.deviation    = m_maxDeviation;
      request.type_filling = GetBestFillingMode();
      request.type_time    = ORDER_TIME_GTC;
      
      ResetLastError();
      if(!OrderCheck(request, checkResult))
      {
         reason = StringFormat("OrderCheck failed with retcode %d (%s), SysError: %d", 
                               checkResult.retcode, checkResult.comment, GetLastError());
         return false;
      }
      
      if(checkResult.retcode != 0)
      {
         reason = StringFormat("OrderCheck returned rejection retcode %d (%s)", checkResult.retcode, checkResult.comment);
         return false;
      }
      
      reason = "";
      return true;
   }
   
   // Executes trade and reconciles result
   bool ExecuteMarketOrder(ENUM_ORDER_TYPE orderType, double volume, double price, double sl, double tp,
                           uint &outRetcode, ulong &outDealTicket, ulong &outPositionTicket, 
                           double &outActualEntry, double &outSlippage, string &resultStr, string &rejectionReason)
   {
      MqlTradeRequest request;
      MqlTradeResult  result;
      ZeroMemory(request);
      ZeroMemory(result);
      
      request.action       = TRADE_ACTION_DEAL;
      request.symbol       = m_symbol;
      request.magic        = m_magic;
      request.volume       = volume;
      request.type         = orderType;
      request.price        = price;
      request.sl           = sl;
      request.tp           = tp;
      request.deviation    = m_maxDeviation;
      request.type_filling = GetBestFillingMode();
      request.type_time    = ORDER_TIME_GTC;
      request.comment      = "H1M15_Pullback";
      
      ResetLastError();
      bool sendSuccess = OrderSend(request, result);
      outRetcode = result.retcode;
      
      if(!sendSuccess || (result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED))
      {
         resultStr = StringFormat("OrderSend failed (Retcode %d: %s)", result.retcode, result.comment);
         rejectionReason = resultStr;
         return false;
      }
      
      outDealTicket     = result.deal;
      outPositionTicket = (result.order > 0) ? result.order : 0;
      outActualEntry    = (result.price > 0) ? result.price : price;
      
      // Calculate estimated slippage
      outSlippage = MathAbs(outActualEntry - price);
      
      resultStr = StringFormat("Executed successfully. Deal: %I64u, Price: %.5f, Vol: %.2f", 
                               outDealTicket, outActualEntry, volume);
      rejectionReason = "";
      return true;
   }
};
