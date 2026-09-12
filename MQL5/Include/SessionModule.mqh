//+------------------------------------------------------------------+
//|                                                SessionModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

enum ENUM_SESSION_PROFILE
{
   SESSION_PROFILE_CUSTOM           = 0, // Custom UTC Start/End Inputs
   SESSION_PROFILE_FULL_DAY         = 1, // Full London + NY Window (08:00 - 16:00 UTC)
   SESSION_PROFILE_LONDON_MORNING   = 2, // London Morning Only (08:00 - 12:00 UTC)
   SESSION_PROFILE_LONDON_NY_OVERLAP= 3, // London / NY Overlap (12:00 - 16:00 UTC)
   SESSION_PROFILE_NY_CONTINUATION  = 4  // New York Continuation (16:00 - 19:00 UTC)
};

//+------------------------------------------------------------------+
//| CSessionModule Class                                             |
//+------------------------------------------------------------------+
class CSessionModule
{
private:
   string               m_symbol;
   int                  m_serverUtcOffset;         // Offset: BrokerServerTime - UTC (Hours). Exness = 0.
   ENUM_SESSION_PROFILE m_sessionProfile;
   int                  m_startHourUTC;
   int                  m_startMinUTC;
   int                  m_endHourUTC;
   int                  m_endMinUTC;
   bool                 m_filterWeekendCrypto;     // Mon-Fri restriction for crypto
   bool                 m_enableRolloverBlock;
   int                  m_rolloverBlockBeforeMins; // Minutes before 00:00 server time
   int                  m_rolloverBlockAfterMins;  // Minutes after 00:00 server time
   
public:
   CSessionModule() :
      m_symbol(""),
      m_serverUtcOffset(0),
      m_sessionProfile(SESSION_PROFILE_FULL_DAY),
      m_startHourUTC(8),
      m_startMinUTC(0),
      m_endHourUTC(16),
      m_endMinUTC(0),
      m_filterWeekendCrypto(true),
      m_enableRolloverBlock(true),
      m_rolloverBlockBeforeMins(15),
      m_rolloverBlockAfterMins(15)
   {}
   
   void Init(string symbol, int serverUtcOffset, int startH, int startM, int endH, int endM, 
             bool weekendCryptoBlock = true, bool rolloverBlock = true, int roBefore = 15, int roAfter = 15,
             ENUM_SESSION_PROFILE profile = SESSION_PROFILE_FULL_DAY)
   {
      m_symbol = symbol;
      m_serverUtcOffset = serverUtcOffset;
      m_sessionProfile = profile;
      
      switch(profile)
      {
         case SESSION_PROFILE_LONDON_MORNING:
            m_startHourUTC = 8;  m_startMinUTC = 0;
            m_endHourUTC   = 12; m_endMinUTC   = 0;
            break;
         case SESSION_PROFILE_LONDON_NY_OVERLAP:
            m_startHourUTC = 12; m_startMinUTC = 0;
            m_endHourUTC   = 16; m_endMinUTC   = 0;
            break;
         case SESSION_PROFILE_NY_CONTINUATION:
            m_startHourUTC = 16; m_startMinUTC = 0;
            m_endHourUTC   = 19; m_endMinUTC   = 0;
            break;
         case SESSION_PROFILE_FULL_DAY:
            m_startHourUTC = 8;  m_startMinUTC = 0;
            m_endHourUTC   = 16; m_endMinUTC   = 0;
            break;
         case SESSION_PROFILE_CUSTOM:
         default:
            m_startHourUTC = startH; m_startMinUTC = startM;
            m_endHourUTC   = endH;   m_endMinUTC   = endM;
            break;
      }
      
      m_filterWeekendCrypto = weekendCryptoBlock;
      m_enableRolloverBlock = rolloverBlock;
      m_rolloverBlockBeforeMins = roBefore;
      m_rolloverBlockAfterMins = roAfter;
   }
   
   // Converts broker server time to UTC datetime
   datetime GetCurrentUTCTime(datetime serverTime = 0)
   {
      if(serverTime == 0)
         serverTime = TimeCurrent();
      return serverTime - (m_serverUtcOffset * 3600);
   }
   
   // Checks broker session availability using SymbolInfoSessionTrade across ALL daily sessions
   bool IsBrokerTradingAllowed(datetime serverTime, string &reason)
   {
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      
      datetime from, to;
      ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)dt.day_of_week;
      long secOfDay = dt.hour * 3600 + dt.min * 60 + dt.sec;
      
      uint sessionIndex = 0;
      bool hasAnySession = false;
      bool insideAnySession = false;
      string sessionHours = "";
      
      while(SymbolInfoSessionTrade(m_symbol, day, sessionIndex, from, to))
      {
         hasAnySession = true;
         MqlDateTime dtFrom, dtTo;
         TimeToStruct(from, dtFrom);
         TimeToStruct(to, dtTo);
         long fromSec = dtFrom.hour * 3600 + dtFrom.min * 60 + dtFrom.sec;
         long toSec   = dtTo.hour * 3600 + dtTo.min * 60 + dtTo.sec;
         if(toSec == 0) toSec = 86400; // Midnight / end of day
         
         sessionHours += StringFormat("[%02d:%02d-%02d:%02d] ", dtFrom.hour, dtFrom.min, dtTo.hour, dtTo.min);
         
         if(secOfDay >= fromSec && secOfDay < toSec)
         {
            insideAnySession = true;
            break;
         }
         sessionIndex++;
      }
      
      if(!hasAnySession)
      {
         reason = "Broker trade session closed for day " + IntegerToString(dt.day_of_week);
         return false;
      }
      
      if(!insideAnySession)
      {
         reason = StringFormat("Outside broker session %s(Current: %02d:%02d)", sessionHours, dt.hour, dt.min);
         return false;
      }
      
      return true;
   }
   
   // Checks rollover and daily-break blackout around session boundaries & midnight
   bool IsInRolloverBlackout(datetime serverTime, string &reason)
   {
      if(!m_enableRolloverBlock) return false;
      
      MqlDateTime dt;
      TimeToStruct(serverTime, dt);
      long secOfDay = dt.hour * 3600 + dt.min * 60 + dt.sec;
      int currentMinsOfDay = dt.hour * 60 + dt.min;
      
      // 1. Midnight rollover blackout
      if(currentMinsOfDay >= (1440 - m_rolloverBlockBeforeMins))
      {
         reason = StringFormat("Rollover blackout: %d mins before midnight", 1440 - currentMinsOfDay);
         return true;
      }
      if(currentMinsOfDay < m_rolloverBlockAfterMins)
      {
         reason = StringFormat("Rollover blackout: %d mins after midnight", currentMinsOfDay);
         return true;
      }
      
      // 2. Broker instrument daily break blackout derived from SymbolInfoSessionTrade
      ENUM_DAY_OF_WEEK day = (ENUM_DAY_OF_WEEK)dt.day_of_week;
      datetime from, to;
      uint sessionIndex = 0;
      long beforeBufferSec = m_rolloverBlockBeforeMins * 60;
      long afterBufferSec  = m_rolloverBlockAfterMins * 60;
      
      while(SymbolInfoSessionTrade(m_symbol, day, sessionIndex, from, to))
      {
         MqlDateTime dtFrom, dtTo;
         TimeToStruct(from, dtFrom);
         TimeToStruct(to, dtTo);
         long fromSec = dtFrom.hour * 3600 + dtFrom.min * 60 + dtFrom.sec;
         long toSec   = dtTo.hour * 3600 + dtTo.min * 60 + dtTo.sec;
         if(toSec == 0) toSec = 86400;
         
         // If approaching the end of a session before a break
         if(toSec < 86400 && secOfDay >= (toSec - beforeBufferSec) && secOfDay < toSec)
         {
            reason = StringFormat("Session break blackout: %d mins before session close at %02d:%02d",
                                  (int)((toSec - secOfDay) / 60), dtTo.hour, dtTo.min);
            return true;
         }
         // If just opened after a session break
         if(fromSec > 0 && secOfDay >= fromSec && secOfDay < (fromSec + afterBufferSec))
         {
            reason = StringFormat("Session break blackout: %d mins after session open at %02d:%02d",
                                  (int)((secOfDay - fromSec) / 60), dtFrom.hour, dtFrom.min);
            return true;
         }
         sessionIndex++;
      }
      
      return false;
   }
   
   // Checks configured UTC window
   bool IsInConfiguredUTCWindow(datetime utcTime, string &reason)
   {
      MqlDateTime dt;
      TimeToStruct(utcTime, dt);
      
      // Check Monday to Friday restriction if applicable (Crypto or general)
      if(m_filterWeekendCrypto)
      {
         if(dt.day_of_week == 0 || dt.day_of_week == 6) // Sunday = 0, Saturday = 6
         {
            reason = "Trading blocked on weekends (UTC Sat/Sun)";
            return false;
         }
      }
      
      int currentMin = dt.hour * 60 + dt.min;
      int startMin   = m_startHourUTC * 60 + m_startMinUTC;
      int endMin     = m_endHourUTC * 60 + m_endMinUTC;
      
      // Window within same day
      if(startMin <= endMin)
      {
         if(currentMin < startMin || currentMin >= endMin)
         {
            reason = StringFormat("Outside UTC session (%02d:%02d - %02d:%02d UTC, Current: %02d:%02d)", 
                                  m_startHourUTC, m_startMinUTC, m_endHourUTC, m_endMinUTC, dt.hour, dt.min);
            return false;
         }
      }
      else // Window crosses midnight
      {
         if(currentMin < startMin && currentMin >= endMin)
         {
            reason = StringFormat("Outside overnight UTC session (%02d:%02d - %02d:%02d UTC, Current: %02d:%02d)", 
                                  m_startHourUTC, m_startMinUTC, m_endHourUTC, m_endMinUTC, dt.hour, dt.min);
            return false;
         }
      }
      
      return true;
   }
   
   // Complete session validation combining all checks
   bool CheckSession(string &statusStr, string &rejectionReason)
   {
      datetime serverTime = TimeCurrent();
      datetime utcTime = GetCurrentUTCTime(serverTime);
      
      // 1. Rollover Check
      if(IsInRolloverBlackout(serverTime, rejectionReason))
      {
         statusStr = "RolloverBlackout";
         return false;
      }
      
      // 2. Broker Session Check
      if(!IsBrokerTradingAllowed(serverTime, rejectionReason))
      {
         statusStr = "BrokerSessionClosed";
         return false;
      }
      
      // 3. Configured UTC Window Check
      if(!IsInConfiguredUTCWindow(utcTime, rejectionReason))
      {
         statusStr = "OutsideUTCWindow";
         return false;
      }
      
      statusStr = "ActiveSession";
      rejectionReason = "";
      return true;
   }
};
