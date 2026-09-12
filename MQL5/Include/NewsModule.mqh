//+------------------------------------------------------------------+
//|                                                   NewsModule.mqh |
//|                                  Copyright 2026, Institutional EA|
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Institutional EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

struct HistoricalNewsEvent
{
   datetime time;
   string   currency;
   int      importance;
   string   name;
};

enum ENUM_NEWS_FILTER_MODE
{
   NEWS_FILTER_ALL_HIGH_IMPACT = 0, // All High-Impact Calendar Events
   NEWS_FILTER_TIER1_CORE_ONLY = 1  // Tier 1 Core Only (FOMC, CPI, NFP, Fed Rate Decisions)
};

//+------------------------------------------------------------------+
//| CNewsModule Class                                                |
//+------------------------------------------------------------------+
class CNewsModule
{
private:
   bool                  m_enabled;
   bool                  m_enableInTester;
   ENUM_NEWS_FILTER_MODE m_filterMode;
   int                   m_blackoutBeforeMins;
   int                   m_blackoutAfterMins;
   string                m_currencyFilter;       // Primary currency e.g. "USD"
   string                m_secondaryCurrency;    // Base or quote currency of symbol
   HistoricalNewsEvent   m_historicalEvents[];
   int                   m_historicalCount;
   
   // Checks if event is a Tier 1 macro event (FOMC, NFP, CPI, Rate Decisions)
   bool IsTier1Event(string name)
   {
      string lower = name;
      StringToLower(lower);
      if(StringFind(lower, "fomc") >= 0 ||
         StringFind(lower, "fed") >= 0 ||
         StringFind(lower, "cpi") >= 0 ||
         StringFind(lower, "non-farm") >= 0 ||
         StringFind(lower, "payroll") >= 0 ||
         StringFind(lower, "interest rate") >= 0 ||
         StringFind(lower, "rate decision") >= 0)
      {
         return true;
      }
      return false;
   }
   
   // Loads historical news CSV if in tester mode
   void LoadHistoricalNews(string filename = "news_events.csv")
   {
      m_historicalCount = 0;
      ArrayResize(m_historicalEvents, 0);
      
      int handle = FileOpen(filename, FILE_READ | FILE_CSV | FILE_ANSI, ',');
      if(handle == INVALID_HANDLE)
      {
         PrintFormat("[NewsModule] Notice: No historical news file '%s' found in MQL5/Files. Tester will bypass news filter.", filename);
         return;
      }
      
      // Read lines: DateTime,Currency,Importance,Name
      while(!FileIsEnding(handle))
      {
         string dtStr   = FileReadString(handle);
         string cur     = FileReadString(handle);
         int    imp     = (int)FileReadNumber(handle);
         string name    = FileReadString(handle);
         
         if(dtStr == "" || dtStr == "DateTime" || dtStr == "Time") continue;
         
         datetime t = StringToTime(dtStr);
         if(t > 0)
         {
            int idx = ArraySize(m_historicalEvents);
            ArrayResize(m_historicalEvents, idx + 1);
            m_historicalEvents[idx].time = t;
            m_historicalEvents[idx].currency = cur;
            m_historicalEvents[idx].importance = imp;
            m_historicalEvents[idx].name = name;
            m_historicalCount++;
         }
      }
      FileClose(handle);
      PrintFormat("[NewsModule] Loaded %d historical news events from %s for Tester replay", m_historicalCount, filename);
   }
   
public:
   CNewsModule() :
      m_enabled(true),
      m_enableInTester(false),
      m_filterMode(NEWS_FILTER_ALL_HIGH_IMPACT),
      m_blackoutBeforeMins(30),
      m_blackoutAfterMins(30),
      m_currencyFilter("USD"),
      m_secondaryCurrency(""),
      m_historicalCount(0)
   {}
   
   void Init(bool enabled, bool enableInTester, int beforeMins, int afterMins, string primaryCur, string secondaryCur,
             ENUM_NEWS_FILTER_MODE filterMode = NEWS_FILTER_ALL_HIGH_IMPACT)
   {
      m_enabled = enabled;
      m_enableInTester = enableInTester;
      m_filterMode = filterMode;
      m_blackoutBeforeMins = beforeMins;
      m_blackoutAfterMins = afterMins;
      m_currencyFilter = primaryCur;
      m_secondaryCurrency = secondaryCur;
      
      if(MQLInfoInteger(MQL_TESTER) && m_enableInTester)
      {
         LoadHistoricalNews("news_events.csv");
      }
   }
   
   // Evaluates if current time is inside a high-impact news blackout window
   // Returns: true if safe (no blackout), false if trade must be rejected
   bool IsNewsSafe(string &statusStr, string &rejectionReason)
   {
      if(!m_enabled)
      {
         statusStr = "NewsFilterDisabled";
         return true;
      }
      
      // Trade server time is required for MQL5 calendar events
      datetime currentTime = TimeTradeServer();
      if(currentTime == 0) currentTime = TimeCurrent();
      
      // Handle MT5 Strategy Tester mode
      if(MQLInfoInteger(MQL_TESTER))
      {
         if(!m_enableInTester)
         {
            statusStr = "BypassedInTester";
            return true;
         }
         
         // If historical events are loaded for replay
         if(m_historicalCount > 0)
         {
            for(int k = 0; k < m_historicalCount; k++)
            {
               if(m_historicalEvents[k].importance >= CALENDAR_IMPORTANCE_HIGH)
               {
                  if(m_filterMode == NEWS_FILTER_TIER1_CORE_ONLY && !IsTier1Event(m_historicalEvents[k].name))
                     continue;
                  if(m_historicalEvents[k].currency == m_currencyFilter || 
                     (m_secondaryCurrency != "" && m_historicalEvents[k].currency == m_secondaryCurrency))
                  {
                     datetime eventTime = m_historicalEvents[k].time;
                     if(currentTime >= (eventTime - m_blackoutBeforeMins * 60) &&
                        currentTime <= (eventTime + m_blackoutAfterMins * 60))
                     {
                        statusStr = "HighImpactBlackout";
                        rejectionReason = StringFormat("Historical news replay: '%s' [%s] at %s", 
                                                       m_historicalEvents[k].name, m_historicalEvents[k].currency,
                                                       TimeToString(eventTime, TIME_DATE | TIME_MINUTES));
                        return false;
                     }
                  }
               }
            }
            statusStr = "NewsClear";
            rejectionReason = "";
            return true;
         }
         else
         {
            statusStr = "BypassedInTester";
            return true;
         }
      }
      
      datetime fromTime = currentTime - (m_blackoutAfterMins * 60);
      datetime toTime   = currentTime + (m_blackoutBeforeMins * 60);
      
      MqlCalendarValue values[];
      ResetLastError();
      
      // Request calendar events within the search window for primary currency (USD)
      int totalEventsUSD = CalendarValueHistory(values, fromTime, toTime, NULL, m_currencyFilter);
      
      if(totalEventsUSD < 0)
      {
         int err = GetLastError();
         statusStr = "CalendarRequestFailed";
         rejectionReason = StringFormat("Calendar query failed for %s (Error %d)", m_currencyFilter, err);
         return false;
      }
      
      // Check USD events for High Impact
      for(int i = 0; i < totalEventsUSD; i++)
      {
         MqlCalendarEvent event;
         if(CalendarEventById(values[i].event_id, event))
         {
            if(event.importance == CALENDAR_IMPORTANCE_HIGH)
            {
               if(m_filterMode == NEWS_FILTER_TIER1_CORE_ONLY && !IsTier1Event(event.name))
                  continue;
               datetime eventTime = values[i].time;
               if(currentTime >= (eventTime - m_blackoutBeforeMins * 60) &&
                  currentTime <= (eventTime + m_blackoutAfterMins * 60))
               {
                  statusStr = "HighImpactBlackout";
                  rejectionReason = StringFormat("High impact news '%s' [%s] at %s (Window: -%dm / +%dm)", 
                                                 event.name, m_currencyFilter, 
                                                 TimeToString(eventTime, TIME_DATE | TIME_MINUTES),
                                                 m_blackoutBeforeMins, m_blackoutAfterMins);
                  return false;
               }
            }
         }
      }
      
      // If secondary currency is configured and different from primary
      if(m_secondaryCurrency != "" && m_secondaryCurrency != m_currencyFilter)
      {
         MqlCalendarValue secValues[];
         ResetLastError();
         int totalEventsSec = CalendarValueHistory(secValues, fromTime, toTime, NULL, m_secondaryCurrency);
         if(totalEventsSec > 0)
         {
            for(int j = 0; j < totalEventsSec; j++)
            {
               MqlCalendarEvent secEvent;
               if(CalendarEventById(secValues[j].event_id, secEvent))
               {
                  if(secEvent.importance == CALENDAR_IMPORTANCE_HIGH)
                  {
                     if(m_filterMode == NEWS_FILTER_TIER1_CORE_ONLY && !IsTier1Event(secEvent.name))
                        continue;
                     datetime eventTime = secValues[j].time;
                     if(currentTime >= (eventTime - m_blackoutBeforeMins * 60) &&
                        currentTime <= (eventTime + m_blackoutAfterMins * 60))
                     {
                        statusStr = "HighImpactBlackout";
                        rejectionReason = StringFormat("High impact news '%s' [%s] at %s", 
                                                       secEvent.name, m_secondaryCurrency, 
                                                       TimeToString(eventTime, TIME_DATE | TIME_MINUTES));
                        return false;
                     }
                  }
               }
            }
         }
      }
      
      statusStr = "NewsClear";
      rejectionReason = "";
      return true;
   }
};
