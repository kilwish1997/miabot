The project has a good engineering skeleton: closed-candle signals, modular separation, broker preflight, structured logging, risk-based sizing, and active position management. However, the strategy is not yet demonstrably “institutional-grade.” Modularity and 19 filters do not prove an edge.

The main problems are:

1. The specification contains contradictory live parameters.
2. Several filters are likely suppressing valid trades unnecessarily.
3. The exit logic conflicts with the stated 4R target.
4. The session and news logic need more robust time handling.
5. The EA needs a signal funnel and ablation analysis before deciding which filters to relax.

You can increase trade frequency without increasing risk by adding controlled entry models and removing unnecessary rejection bias. Do not simply lower every threshold.

## 1. Critical Problems to Fix First

### P0: Conflicting parameters

The guide contains different values for the same behavior:

| Parameter | One section | Parameter catalog |
|---|---:|---:|
| TP multiplier | `1.8R` | `4.0R` |
| Daily loss percentage | `1%` | `10%` |
| Weekly loss percentage | `3%` | `20%` |
| Drawdown kill switch | `5%` | `20%` |
| Risk percent | `0.25%`, max `0.50%` | `0.25%` |

This is dangerous. A backtest using one preset and a live EA using another can produce completely different behavior.

Create one canonical configuration and print the effective values during `OnInit()`:

```text
RiskPercent=0.25
MaxRiskMoney=50.00
TPMultiplier=1.80
MaxDailyLossPct=1.00
MaxWeeklyLossPct=3.00
DrawdownKillSwitchPct=5.00
```

Also reject initialization if unsafe combinations are detected. For example:

```text
TPMultiplier <= 0
RiskPercent > 0.50
MaxDailyLossPct > MaxWeeklyLossPct
TimeExitBars <= 0
MinADX < 0
```

The preset, README, technical guide, and code comments must all be generated from or checked against the same source of truth.

### P0: Fixed rollover logic is not aligned with current Exness gold hours

Exness states that its trading servers use UTC+0, but its instrument schedule has summer and winter periods. For XAUUSD, the official daily break is currently listed as `20:58-22:02` during summer and `21:58-23:02` during winter. On September 11, 2026, the summer schedule applies. ([get.exness.help](https://get.exness.help/hc/en-us/articles/4405235684498-Instrument-trading-hours?utm_source=openai))

Your fixed blackout of `23:45-00:15` is therefore not a reliable gold rollover filter. It may block a period when gold is already closed while failing to represent the actual gold daily break.

Use three separate concepts:

1. Broker availability from `SymbolInfoSessionTrade`.
2. Strategy trading windows such as London and New York.
3. A broker-maintenance or spread blackout derived from the actual symbol schedule.

Do not treat `InpBrokerServerUTCOffset=0` as sufficient. The server timezone can be UTC+0 while instrument hours still change by season.

### P0: Time exit calculation may not equal 12 completed bars

This logic:

```cpp
int completedBars = iBarShift(m_symbol, PERIOD_M15, openTime, false);
if(completedBars >= 12)
```

does not necessarily measure 12 fully completed M15 candles. `iBarShift()` returns a bar index. If the position opens five minutes into a candle, the index can reach `12` before a full three hours have elapsed.

Use completed M15 boundaries instead:

```cpp
datetime now = TimeTradeServer();
int elapsedBars = (int)((now - openTime) / PeriodSeconds(PERIOD_M15));

if(elapsedBars >= InpTimeExitBars)
   ClosePositionMarket(...);
```

If you specifically want twelve completed candles after the entry candle, calculate from the next M15 bar open rather than directly from `openTime`.

### P0: Stop-level validation must use current executable prices

The guide says the stop distance must be greater than the broker stop level. That is not sufficient if you only compare:

```text
EntryPrice - StopLoss
```

For a buy, the broker checks the distance from the current `Bid` to the SL. For a sell, it checks the distance from the current `Ask` to the SL. The freeze level also applies to position modifications. MQL5 defines these distances relative to the current market price, not simply the original entry price. ([mql5.com](https://www.mql5.com/en/docs/constant_indices?utm_source=openai))

At both initial placement and trailing modification, check:

```text
Buy:
Bid - SL >= max(StopsLevel, FreezeLevel) * Point

Sell:
SL - Ask >= max(StopsLevel, FreezeLevel) * Point
```

Also validate TP against broker stop restrictions. `OrderCheck()` should remain the final authority.

### P0: News testing is not equivalent to live news filtering

MQL5 economic-calendar timestamps use trade-server time, not the user's local time. ([mql5.com](https://www.mql5.com/en/docs/calendar?utm_source=openai))

MQL5 also documents that economic-calendar functions cannot be used directly in the Strategy Tester. Historical news must be exported and replayed from an external file if you want a realistic news-filter backtest. ([mql5.com](https://www.mql5.com/en/book/advanced/calendar?utm_source=openai))

Your current tester behavior:

```text
InpNewsFilterInTester=false
```

means the backtest trades through events that live mode will reject. This makes the backtest and live strategy different.

Use two tests:

1. Baseline without news filtering.
2. Historical news-replay mode using a saved event file.

Then compare:

```text
Trade count
Net expectancy
News-period drawdown
Average spread
Maximum adverse excursion
```

### P1: Slippage sizing formula needs dimensional verification

This expression is potentially incorrect:

```cpp
slippagePoints * tickValue
```

A point is not always the same as a tick size, and tick value may be quoted per tick size rather than per point.

A safer approach is to calculate the adverse fill price and call `OrderCalcProfit()` again. MQL5 documents `OrderCalcProfit()` as an account-currency estimate for a specified order, symbol, volume, open price, and close price. ([mql5.com](https://www.mql5.com/en/docs/trading/ordercalcprofit?utm_source=openai))

For a buy:

```text
AdverseEntry = EntryPrice + SlippagePoints * Point
```

For a sell:

```text
AdverseEntry = EntryPrice - SlippagePoints * Point
```

Then calculate the loss from the adverse entry to the SL. This handles symbol-specific contract specifications more safely.

### P1: `OrderCheck()` does not guarantee execution

`OrderCheck()` validates the request and funds, but MQL5 explicitly states that a successful check does not guarantee that the order will be executed. ([mql5.com](https://www.mql5.com/en/docs/trading/ordercheck?utm_source=openai))

Your reconciliation must be based on `OnTradeTransaction()` and actual deal data:

```text
Requested price
Actual fill price
Actual volume
Commission
Swap
Deal retcode
Position ticket
Final exit price
Realized R
```

Do not rely only on `MqlTradeResult` from the original `OrderSend()` call.

## 2. The Strategy Edge

### What is good

The following decisions are sound:

- Using H1 and M15 closed candles reduces intra-candle repainting.
- Combining trend, pullback, and breakout is logically coherent.
- Structure-based stops are better than using an arbitrary fixed number of points.
- `OrderCalcProfit()` is preferable to manually assuming a fixed gold pip value.
- Strict downward volume rounding protects the risk budget.
- Risk controls, margin checks, and trade logging are valuable.
- Break-even and trailing management are separated from signal generation.

### What is weak

#### The pullback rule is too shallow

This condition:

```text
At least one candle in shifts 2-4 touched EMA20
```

does not prove a meaningful pullback. A wick can barely touch the EMA and still qualify.

It also does not distinguish:

- A clean bullish rejection.
- A deep bearish reversal.
- A low-range sideways candle.
- A high-volatility news candle.

Improve it by defining a pullback zone:

```text
Buy pullback:
Low <= EMA20 + 0.10 to 0.20 ATR
Close >= EMA20 - 0.50 ATR
```

Then require a rejection or resumption characteristic:

```text
Bullish close
Close in upper 40% of candle range
Body larger than a minimum percentage of ATR
```

Do not require every condition in the first version. Test them as separate setup variants.

#### The breakout rule can trigger on noise

This rule:

```text
Close[1] > High[2]
```

is simple, but it does not measure breakout quality. A one-point close above a weak candle high can trigger a trade.

Add optional breakout quality fields:

```text
BreakoutDistance = Close[1] - High[2]
BreakoutDistance / ATR
BreakoutCandleBody / ATR
CloseLocationValue
```

You can then create two setups:

```text
Core breakout:
BreakoutDistance >= 0.05 ATR
```

```text
Aggressive breakout:
BreakoutDistance >= 0
Candle closes in upper 35% of its range
Risk is reduced
```

This is better than globally lowering the H1 trend threshold.

#### H1 ADX alone is not enough

`ADX >= 20` is a reasonable starting filter, but it does not tell you whether the trend is strengthening or weakening.

Add one optional trend-quality variant:

```text
EMA50 > EMA200
Close > EMA50
EMA50 slope positive
+DI > -DI
ADX between 17 and 20
```

Use lower risk for this secondary setup. Keep the current `ADX >= 20` rule as the core setup.

## 3. How to Take More Trades Safely

### 1. Make price drift asymmetric

Your current filter rejects both favorable and unfavorable movement:

```text
abs(EntryPrice - SignalClose) <= 0.25 ATR
```

That is not ideal. For a buy, the dangerous movement is upward movement before entry because you are buying at a worse price. For a sell, the dangerous movement is downward movement.

Use:

```text
Buy adverse drift  = Ask - SignalClose
Sell adverse drift = SignalClose - Bid
```

Then use two limits:

```text
Adverse drift <= 0.15 to 0.25 ATR
Total distance from signal <= 0.35 to 0.45 ATR
```

This avoids rejecting a small favorable move while still preventing very late entries. Always use `Ask` for buy execution and `Bid` for sell execution.

### 2. Extend the pullback window from 3 bars to 5 or 6 bars

A three-bar pullback window is likely too restrictive for gold. A normal M15 pullback can develop over 4-6 candles while remaining valid.

Test:

```text
Current: shifts 2-4
Variants: shifts 2-5, shifts 2-6
```

Do not allow unlimited age. The setup should expire after a defined number of bars.

### 3. Add a breakout-retest entry model

Keep the current setup as `SETUP_CLOSE_BREAKOUT`.

Add:

```text
1. M15 closes beyond the breakout level.
2. The next one or two candles retest that level.
3. Price rejects the level in the original direction.
4. Entry occurs on confirmation.
5. Setup expires after two candles.
```

For a buy:

```text
Retest low <= breakout level + tolerance
Retest close > breakout level
```

For a sell:

```text
Retest high >= breakout level - tolerance
Retest close < breakout level
```

This can capture trades missed by the original signal because of spread, price drift, or a fast breakout. Do not enter both the initial breakout and retest version for the same setup.

### 4. Add a lower-timeframe execution variant

Use M15 to define the setup and M5 only to time the entry:

```text
H1 trend
M15 pullback into EMA20 zone
M5 break of local structure
```

This can produce more entries and reduce the delay between the signal and execution. It also introduces more noise, so give it:

```text
Separate setup ID
Separate backtest statistics
Possibly 50% of core risk
```

Do not mix M5 entries into the core results.

### 5. Split the gold session into sub-sessions

Instead of one broad `08:00-16:00` window, measure results by:

```text
London morning
London/New York overlap
New York continuation
```

Then enable only the sub-sessions with positive net expectancy after spread and slippage.

A practical development approach is:

```text
Core session: current window
Optional extension: one additional 60-120 minute block
```

Do not extend the entire day at once. Gold's broker availability and daily break should still come from the symbol's actual trade schedule. Exness lists different summer and winter instrument periods, so session logic should not depend on a permanently fixed broker schedule. ([get.exness.help](https://get.exness.help/hc/en-us/articles/4405235684498-Instrument-trading-hours?utm_source=openai))

### 6. Replace the fixed news blackout with event classes

A fixed `30 minutes before and after every high-impact USD event` can remove too many valid trades.

Use event classes:

| Event type | Suggested development treatment |
|---|---|
| FOMC, CPI, NFP | Strict blackout |
| Retail sales, PPI, ISM | Medium blackout |
| Speeches and secondary events | Spread/volatility confirmation |
| Post-news period | Trade only after spread and ATR normalize |

Instead of automatically waiting 30 minutes after every event, require:

```text
Spread <= normal spread threshold
ATR ratio within allowed band
One completed M15 candle after the event
```

This increases opportunity while preserving protection during the most dangerous releases.

### 7. Test `CooldownBars=0`

A one-bar cooldown can prevent a valid new setup immediately after a trade closes.

You can test:

```text
CooldownBars = 0
```

but retain:

```text
One trade per signal bar
Maximum two trades per day
No immediate re-entry from the same setup ID
Fresh pullback required for re-entry
```

The cooldown should prevent revenge-style repeated entries, not block independent signals.

### 8. Use separate XAUUSD and BTCUSD logic

Gold and Bitcoin should not share the same defaults for:

- ATR behavior.
- Spread limits.
- News sensitivity.
- Session windows.
- Time exits.
- Weekend rules.
- Maximum stop distance.
- Risk scaling.

Exness states that most cryptocurrencies are available 24/7 except maintenance periods, while commodities such as gold have weekend closures and daily breaks. ([get.exness.help](https://get.exness.help/hc/en-us/articles/4405235684498-Instrument-trading-hours?utm_source=openai))

Use separate presets and preferably separate strategy IDs:

```text
XAU_M15_PULLBACK
BTC_M15_PULLBACK
```

Do not use the same `MagicNumber` across multiple symbols unless the exposure manager is intentionally portfolio-wide.

## 4. Exit Logic Needs Reconciliation

The guide contains a major conflict:

```text
TP target described as 1.8R
Parameter catalog default is 4.0R
Time exit is 12 M15 bars
Trailing begins at 1.3R
```

A 4R target with a three-hour time exit and an ATR trail starting at 1.3R may be internally incompatible. Many trades will either:

- Exit at the trail before reaching 4R.
- Time out before reaching 4R.
- Move to break-even and get stopped during a normal gold retracement.

Before costs:

```text
1.8R target requires approximately 35.7% wins to break even.
4.0R target requires 20.0% wins to break even.
```

Those are not equivalent strategies. Test them separately.

Recommended exit variants:

### Variant A: Fixed target

```text
TP: 1.8R or 2.2R
Break-even: 1.2R to 1.4R
Trail activation: 1.6R to 2.0R
Time exit: 16 to 24 M15 bars
```

### Variant B: Partial exit

```text
Close 50% at 1.2R
Move stop after confirmation
Trail the remaining 50% by ATR
Time exit after 16 to 24 bars
```

### Variant C: Structure target

```text
Target the next H1 swing or liquidity area
Require minimum reward of 1.5R
Skip trades with insufficient room
```

For gold, I would test the partial-exit model first. It gives the strategy a way to bank profit while still allowing a strong trend to produce a large winner.

Also consider moving break-even later. A break-even trigger at exactly `1.0R` may be too sensitive to ordinary pullbacks. Test `1.2R`, `1.3R`, and `1.5R`.

Use closed ATR values for trailing, preferably ATR shift 1, and avoid sending a modification on every tick. Update on a new M15 candle unless an emergency protection action is required.

## 5. Suggested Gold Test Ranges

These are development ranges, not live recommendations.

| Parameter | Current | Test range |
|---|---:|---:|
| H1 minimum ADX | 20 | Core 20, secondary 17-19 with slope/DMI |
| Pullback lookback | 3 bars | 3, 4, 5, 6 |
| EMA pullback | Exact touch | EMA zone of 0.10-0.20 ATR |
| Price drift | Absolute 0.25 ATR | Asymmetric adverse drift 0.15-0.25 ATR |
| ATR regime | 0.5-2.0 median | Core 0.5-2.0, adaptive 0.4-2.5 |
| TP | 1.8 or 4.0 conflict | 1.8, 2.2, 2.8, partial exit |
| Break-even | 1.0R | 1.2R, 1.3R, 1.5R |
| Trail trigger | 1.3R | 1.6R, 1.8R, 2.0R |
| Time exit | 12 bars | 16, 20, 24 |
| Cooldown | 1 bar | 0 or 1 |
| Core risk | 0.25% | Keep unchanged during testing |

Do not optimize all parameters simultaneously. That will create a high probability of overfitting.

## 6. Improve the Logging Before Relaxing Filters

Your current CSV logging is useful, but a single first-failure rejection reason is not enough to determine which filters are suppressing trade frequency.

For every raw signal, record:

```text
RawSignalDetected
Direction
SetupType
SignalTime
Session
H1TrendPassed
PullbackPassed
BreakoutPassed
VolatilityPassed
NewsPassed
SpreadPassed
DriftPassed
StopPassed
RiskPassed
MarginPassed
OrderCheckPassed
FirstFailure
AllFailureFlags
```

The EA should evaluate all diagnostic filters for logging, even if it still stops execution after the first hard failure.

Create a rejection funnel:

```text
All M15 bars
-> H1 trend candidates
-> M15 pullbacks
-> M15 breakouts
-> Session eligible
-> News eligible
-> Volatility eligible
-> Spread eligible
-> Drift eligible
-> Stop eligible
-> Risk eligible
-> Orders sent
```

Then calculate rejection percentages by:

```text
Hour
Day of week
Long versus short
ATR regime
News proximity
Session
Setup type
Month
```

This will tell you whether the real bottleneck is:

- News filtering.
- Spread filtering.
- Price drift.
- Stop distance.
- Minimum lot size.
- Session hours.
- The actual strategy pattern.

Without this funnel, relaxing filters is guesswork.

## 7. Backtest and Validation Requirements

Real-tick testing is appropriate for a tick-managed EA, but it is not proof that live execution will match. MQL5 documents that real-tick testing uses historical tick data and historical spread; it does not recreate all live execution conditions such as current broker latency and actual slippage. ([mql5.com](https://www.mql5.com/en/docs/runtime/testing?utm_source=openai))

Run these tests:

1. Baseline current strategy.
2. Baseline with realistic commission and spread.
3. Baseline with randomized adverse slippage.
4. News-replay version.
5. Each new setup variant separately.
6. Walk-forward testing with untouched out-of-sample periods.
7. Monte Carlo trade-order and slippage stress.
8. Forward demo testing under the exact intended broker account type.

Measure:

```text
Trades per month
Net expectancy in R
Profit factor
Average win and loss in R
Maximum drawdown
Maximum consecutive losses
Average spread at entry
Average slippage
Percentage of trades stopped at break-even
Average MFE and MAE
Time-in-trade
Results by session
Results by ATR regime
Results by setup type
```

Do not select a configuration because it produces the most trades. Select the configuration with the best combination of:

```text
Positive net expectancy after costs
Stable results across parameter neighbors
Acceptable drawdown
Acceptable execution sensitivity
Adequate out-of-sample performance
```

## Recommended Development Order

1. Unify all contradictory parameters.
2. Fix session, stop-level, time-exit, and news-time handling.
3. Verify actual commission, slippage, fill price, and position reconciliation.
4. Add full signal-funnel diagnostics.
5. Test asymmetric price drift.
6. Extend the pullback window to 5-6 bars.
7. Add the breakout-retest setup.
8. Test separate exit models.
9. Add an M5 execution variant only after the M15 core is stable.
10. Create separate XAUUSD and BTCUSD presets.

The most promising frequency improvements are not increasing risk or weakening every filter. They are:

- Extending the pullback validity window.
- Using a pullback zone instead of an exact EMA touch.
- Making drift rejection asymmetric.
- Adding a breakout-retest state machine.
- Segmenting sessions.
- Using event-specific news handling.
- Allowing fresh re-entry setups after a completed trade.

The immediate priority is correctness. Until the parameter conflicts, session schedule, time exit, and news testing are fixed, any optimization result should be treated as unreliable.