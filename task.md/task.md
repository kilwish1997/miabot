# Task: Build a Conservative MT5 Trend Pullback Expert Advisor

## Role

Act as a senior MQL5 developer, quantitative trading systems engineer, risk-control specialist, and code reviewer.

Build a conservative, low-frequency MetaTrader 5 Expert Advisor based on the strategy and requirements below.

The EA is intended for research, backtesting, and demo validation. It must not claim or imply guaranteed profitability. It must prioritize capital preservation, broker compatibility, correct position sizing, and safe failure behavior.

## Primary Goal

Implement an MT5 Expert Advisor named:

`H1TrendM15PullbackBreakoutEA`

The EA must:

- Trade one configured symbol at a time.
- Use H1 for trend direction.
- Use M15 for entries.
- Evaluate entry signals only after a completed M15 candle.
- Allow a maximum of one open position.
- Use ATR and market structure for stop-loss placement.
- Calculate lot size from the broker's actual symbol specifications.
- Risk approximately 0.25% of account equity per trade by default.
- Reject trades when the broker's minimum volume would exceed the allowed risk.
- Use spread, margin, news, daily-loss, and drawdown filters.
- Never use martingale, grid trading, averaging down, or forced entries.
- Attach the stop-loss and take-profit with the initial order.
- Manage open positions on every tick.
- Log every valid signal, rejected signal, order attempt, and execution result.

The EA must fail closed. If a safety-critical value cannot be calculated or verified, it must reject the new trade and record the reason.

## Scope

Implement version 1 for a single symbol and one strategy instance.

The EA must support:

- Gold symbols such as `XAUUSD`.
- Crypto symbols such as `BTCUSD` or `ETHUSD`, provided the broker supports them.
- Broker-specific contract sizes, tick sizes, tick values, volume limits, margin rules, trading sessions, and stop-distance rules.

Do not assume that:

- `0.01` lots has the same value on every symbol.
- One pip or point has a universal monetary value.
- Gold always uses two decimal places.
- Crypto symbols use the same contract specification as forex or gold.
- The broker's server time is UTC.
- A successful MQL5 method call means that the trade was executed.

## Strategy Configuration

Expose the following inputs where appropriate.

### General settings

```text
Trade symbol: configured input; default to the chart symbol if empty
Magic number: unique configurable integer
Risk per trade: 0.25%
Maximum permitted risk per trade: 0.50%
Maximum open positions: 1
Maximum one position per symbol: enabled by default
Cooldown after a completed trade: 1 completed M15 bar
Allow live trading: disabled by default unless explicitly enabled by the user
The EA must not scan multiple symbols in version 1.

Timeframes
Trend timeframe: H1
Entry timeframe: M15
The EA must use closed candles for all signal calculations.

The forming candle must not be used to generate an entry signal.

Indicator Settings
Use the following initial values:

H1 fast EMA: 50
H1 slow EMA: 200
M15 pullback EMA: 20
H1 ADX period: 14
Minimum ADX: 20
M15 ATR period: 14
ATR comparison lookback: 50 completed M15 bars
All values must be configurable inputs, but the EA should start with the defaults above.

Do not add extra indicators unless they are necessary for implementation or explicitly requested.

Trading Session
Use UTC-based session inputs internally.

Default sessions:

Gold:
08:00 to 16:00 UTC

BTCUSD and ETHUSD:
07:00 to 20:00 UTC, Monday through Friday
The session must also pass the broker's current trading-session check.

The implementation must support:

Configurable UTC start and end times.
Configurable broker-server UTC offset for testing.
Correct handling of sessions that cross midnight.
Blocking trades during broker trading breaks.
Blocking new exposure around daily rollover when configured.
The EA must document how the server-time offset is determined in live trading and in the Strategy Tester.

Long Entry Conditions
A long entry may be considered only when every condition below passes.

The terminal is connected.
The symbol is selected and tradeable.
A new M15 bar has started.
The latest M15 bar has fully closed.
The current time is inside the configured trading session.
The broker currently permits trading.
There is no existing EA position.
There is no existing position on the configured symbol when symbol-level blocking is enabled.
The H1 EMA50 is above the H1 EMA200 using the latest closed H1 bar.
The latest closed H1 candle closed above the H1 EMA50.
The latest closed H1 ADX14 is greater than or equal to the configured minimum.
At least one of the three M15 candles before the signal candle touched or moved below its M15 EMA20.
For the pullback test, use completed candles only:

M15 shifts 2, 3, and 4:
low <= EMA20 for that candle
The latest closed M15 candle closes above the previous M15 candle's high.
The latest closed M15 candle closes above its M15 EMA20.
The latest closed M15 ATR14 is within the permitted volatility range.
No high-impact news blackout is active.
The current spread is acceptable.
The calculated stop-loss distance is valid.
The calculated position size is within the account risk limit.
The broker permits the calculated volume.
The required margin is within the configured margin limit.
OrderCheck() passes.
Short Entry Conditions
A short entry may be considered only when every condition below passes.

The terminal is connected.
The symbol is selected and tradeable.
A new M15 bar has started.
The latest M15 bar has fully closed.
The current time is inside the configured trading session.
The broker currently permits trading.
There is no existing EA position.
There is no existing position on the configured symbol when symbol-level blocking is enabled.
The H1 EMA50 is below the H1 EMA200 using the latest closed H1 bar.
The latest closed H1 candle closed below the H1 EMA50.
The latest closed H1 ADX14 is greater than or equal to the configured minimum.
At least one of the three M15 candles before the signal candle touched or moved above its M15 EMA20.
For the pullback test, use completed candles only:

M15 shifts 2, 3, and 4:
high >= EMA20 for that candle
The latest closed M15 candle closes below the previous M15 candle's low.
The latest closed M15 candle closes below its M15 EMA20.
The latest closed M15 ATR14 is within the permitted volatility range.
No high-impact news blackout is active.
The current spread is acceptable.
The calculated stop-loss distance is valid.
The calculated position size is within the account risk limit.
The broker permits the calculated volume.
The required margin is within the configured margin limit.
OrderCheck() passes.
Volatility Filter
Let:

CurrentATR = ATR14 on the latest closed M15 candle
MedianATR = median of ATR14 values from the 50 completed M15 candles immediately before the signal candle
The volatility filter passes only when:

0.5 * MedianATR <= CurrentATR <= 2.0 * MedianATR
The EA must reject the trade when:

There are not enough historical bars.
ATR cannot be calculated.
The median cannot be calculated.
ATR is zero, invalid, or non-finite.
Entry Execution
Enter at the first available tick after the signal M15 candle closes.

Use:

Long entry price  = current Ask
Short entry price = current Bid
Calculate entry distance from the signal candle close.

For a long:

entryDistance = Ask - signalClose
For a short:

entryDistance = signalClose - Bid
Reject the trade when:

entryDistance > 0.25 * CurrentATR
Also reject the trade if the entry price is invalid, stale, or unavailable.

The EA must:

Send only one order request for a signal.
Prevent duplicate orders for the same signal bar.
Use a unique magic number.
Use a broker-compatible filling mode.
Use a configurable maximum deviation.
Attach the initial stop-loss and take-profit.
Inspect the trade-server return code.
Confirm whether a deal or position was actually created.
Reconcile the position after an ambiguous or failed response.
Log the complete request and server response.
Stop-Loss Rules
Use the latest closed M15 ATR14 value.

For a long:

swingLow = lowest low of M15 shifts 1 through 5
structureStop = swingLow - 0.10 * CurrentATR
atrStop = entryPrice - 1.20 * CurrentATR
stopLoss = the lower of structureStop and atrStop
stopDistance = entryPrice - stopLoss
For a short:

swingHigh = highest high of M15 shifts 1 through 5
structureStop = swingHigh + 0.10 * CurrentATR
atrStop = entryPrice + 1.20 * CurrentATR
stopLoss = the higher of structureStop and atrStop
stopDistance = stopLoss - entryPrice
Reject the trade when:

stopDistance <= 0
stopDistance > 2.5 * CurrentATR
The stop-loss must also satisfy:

Broker minimum stop distance.
Broker freeze level.
Symbol tick-size rules.
Directional price constraints.
Current Bid/Ask distance requirements.
Normalize prices using SYMBOL_TRADE_TICK_SIZE.

Price normalization must preserve the risk direction:

Long stop-losses must be rounded downward when necessary.
Short stop-losses must be rounded upward when necessary.
Long take-profits must be rounded upward when necessary.
Short take-profits must be rounded downward when necessary.
After price normalization, recalculate the final stop distance and position risk.

Take-Profit Rules
Use a default target of 1.8R.

riskDistance = abs(entryPrice - stopLoss)

Long:
takeProfit = entryPrice + 1.8 * riskDistance

Short:
takeProfit = entryPrice - 1.8 * riskDistance
The target multiplier must be configurable.

Recommended test range:

1.5R to 2.0R
The take-profit must pass broker stop-distance, freeze-level, and tick-size validation.

Position Management
Manage open positions on every tick.

Break-even
When the position reaches approximately +1.0R:

Move the stop-loss to entry price plus estimated trading costs for a long.
Move the stop-loss to entry price minus estimated trading costs for a short.
Never move the stop farther from the entry.
Do not modify the stop if the broker freeze level or stop-distance rule prevents the modification.
Log every successful or rejected stop modification.
ATR trailing stop
When the position reaches approximately +1.3R:

Trailing distance = 1.5 * latest closed M15 ATR14
For a long:

candidateStop = currentBid - trailingDistance
For a short:

candidateStop = currentAsk + trailingDistance
Only improve the stop:

Long stops may move upward only.
Short stops may move downward only.
The stop must never move farther away from the entry.
The new stop must satisfy broker stop-distance and freeze-level rules.
Time-based exit
Close the position after 12 completed M15 candles if neither the stop-loss nor take-profit has closed it.

The number of completed candles must be calculated from broker/server bar timestamps and must remain correct after an EA restart.

Do not partially close positions in version 1.

Do not add to losing positions.

News Filter
Use the MT5 economic calendar where available.

Initially block new trades around high-impact USD events, including:

U.S. employment releases.
CPI releases.
PCE inflation releases.
Federal Reserve interest-rate decisions.
Federal Reserve press conferences.
Major GDP releases.
Major retail-sales releases.
Default blackout:

30 minutes before the event
30 minutes after the event
Apply the filter to:

Gold.
BTCUSD.
ETHUSD.
The news filter must:

Use trade-server time.
Handle the configured server-time conversion.
Check event importance.
Check the affected currency.
Log the event name, event time, and blackout status.
Block new entries if the calendar request fails.
Continue managing existing positions if the news module fails.
Never widen a stop-loss because of a news event.

Spread Filter
Calculate the actual spread:

spread = Ask - Bid
The default spread rules are:

spread <= 10% of stopDistance
spread <= 15% of CurrentATR
The trade is allowed only when both rules pass.

Use the stricter result.

Do not use a universal hardcoded point or pip limit.

The EA must also reject the trade when:

Bid or Ask is unavailable.
Spread is negative or invalid.
Spread is unusually high relative to the configured symbol.
The market is in a configured rollover or low-liquidity block.
Risk and Position Sizing
Default risk:

RiskPercent = 0.25%
Maximum permitted configurable risk:

0.50%
Reject invalid risk settings above the permitted maximum.

Calculate the money risk from current account equity:

riskMoney = accountEquity * RiskPercent / 100
Use OrderCalcProfit() to calculate the loss of one lot between the planned entry and final stop-loss.

Do not calculate risk from fixed pip tables.

The position-sizing process must:

Read the current symbol specification.
Calculate the final entry, stop, and target prices.
Calculate one-lot loss using OrderCalcProfit().
Add configurable commission and expected slippage estimates.
Calculate raw volume.
Round volume downward to the broker's volume step.
Normalize volume precision.
Ensure volume is not below the broker minimum.
Ensure volume is not above the broker maximum.
Recalculate final risk using the normalized volume.
Reject the trade if final risk exceeds the configured risk budget.
Required symbol properties include:

SYMBOL_POINT
SYMBOL_DIGITS
SYMBOL_TRADE_TICK_SIZE
SYMBOL_TRADE_TICK_VALUE
SYMBOL_TRADE_CONTRACT_SIZE
SYMBOL_VOLUME_MIN
SYMBOL_VOLUME_STEP
SYMBOL_VOLUME_MAX
SYMBOL_TRADE_STOPS_LEVEL
SYMBOL_TRADE_FREEZE_LEVEL
SYMBOL_TRADE_MODE
SYMBOL_TRADE_CALC_MODE
Never round volume upward to satisfy the broker minimum.

Example:

Account equity: $100
Risk percentage: 0.25%
Maximum risk: $0.25
Broker minimum volume risk at the selected stop: $1.20

Required result:
Reject the trade because the minimum valid volume exceeds the risk limit.
Margin Controls
Before sending an order, calculate required margin using OrderCalcMargin().

Default controls:

Maximum required margin: 20% of account equity
Minimum post-trade free margin: 50% of account equity
Minimum post-trade margin level: configurable, default 300%
Reject the trade when:

Margin calculation fails.
Required margin is invalid.
Required margin exceeds the configured limit.
Free margin after entry is too low.
Expected margin level is unsafe.
The broker does not permit the operation.
Do not use high leverage as a strategy objective.

Daily, Weekly, and Drawdown Protection
Implement the following default controls:

Maximum daily loss: 1.0%
Maximum losing trades per broker day: 2
Maximum weekly loss: 3.0%
Drawdown kill switch: 5.0% from equity high-water mark
These controls must block new entries when triggered.

Existing positions must continue to receive normal stop, target, trailing, and time-exit management unless an explicit emergency-close option is enabled.

Daily loss should include current equity deterioration from the beginning of the broker trading day and realized losses from the EA.

The equity high-water mark must persist across EA restarts using a safe terminal global variable or equivalent persistent storage.

When a limit is triggered:

Stop new entries.
Continue managing open positions.
Log the exact limit and measured value.
Send an alert when alerts are enabled.
Do not automatically increase risk or alter strategy parameters.
Required Architecture
Separate the EA into logical modules.

Recommended modules:

SignalModule
MarketStructureModule
RiskModule
PositionSizingModule
NewsModule
SessionModule
ExecutionModule
PositionManagementModule
DrawdownModule
DailyLossModule
LoggingModule
The exact file structure may vary, but responsibilities must remain separated.

Suggested deliverables:

Experts/H1TrendM15PullbackBreakoutEA.mq5
Include/SignalModule.mqh
Include/RiskModule.mqh
Include/PositionSizingModule.mqh
Include/NewsModule.mqh
Include/ExecutionModule.mqh
Include/PositionManagementModule.mqh
Include/LoggingModule.mqh
README.md
config.example.set
backtest-report-template.md
Use existing project conventions if the repository already contains an MQL5 structure.

Startup and Restart Behavior
On initialization, the EA must:

Verify the configured symbol.
Read and log symbol specifications.
Verify required historical data.
Create indicator handles.
Validate all input values.
Detect account margin mode.
Inspect existing positions.
Reconcile any existing position belonging to the EA.
Restore the equity high-water mark.
Restore any required signal or trade state.
Refuse to trade if initialization is incomplete.
The EA must never open a duplicate position after:

A terminal restart.
A VPS restart.
A connection interruption.
A failed or ambiguous order response.
A chart timeframe change.
An EA reinitialization.
Connection and Market Data Safety
Before an entry evaluation, verify:

Terminal connection is active.
The latest tick is recent.
Bid and Ask are valid.
The symbol is selected.
The symbol permits trading.
Required indicator data is available.
Required historical bars exist.
The broker trading session is active.
If any check fails:

Do not open a new trade.
Log the reason.
Continue managing existing positions when possible.
Logging Requirements
Create structured logs in CSV format under the platform's permitted files directory.

Log at minimum:

Timestamp
Broker server time
UTC time when available
Account number or masked account identifier
Symbol
Magic number
Signal bar time
Direction
H1 EMA50
H1 EMA200
H1 ADX
M15 EMA20
M15 ATR
Median ATR
Spread
Signal close
Entry price
Stop-loss
Take-profit
Stop distance
Risk percentage
Risk money
Calculated raw volume
Final volume
Minimum volume
Volume step
Estimated margin
Daily loss status
Weekly loss status
Drawdown status
News status
Session status
Every filter result
Rejection reason
Order request result
Trade-server retcode
Deal ticket
Position ticket
Actual entry price
Actual spread
Estimated slippage
Exit price
Exit reason
Result in account currency
Result in R
Every entry evaluation should expose Boolean filter results such as:

ConnectionOK
DataOK
SessionOK
ExposureOK
DailyLossOK
WeeklyLossOK
DrawdownOK
NewsOK
TrendOK
PullbackOK
BreakoutOK
VolatilityOK
SpreadOK
PriceDistanceOK
StopOK
RiskOK
VolumeOK
MarginOK
OrderCheckOK
Rejected signals must be logged. Do not log only successful trades.

Error Handling
The EA must handle safely:

Missing historical bars.
Invalid indicator handles.
Failed CopyBuffer() calls.
Missing ticks.
Disconnected terminal.
Disabled symbol.
Market closed.
Invalid volume.
Volume below minimum.
Volume above maximum.
Invalid volume step.
Invalid stop distance.
Invalid tick-size normalization.
Insufficient margin.
News-calendar failure.
Failed OrderCheck().
Failed trade request.
Retcode indicating rejection.
Partial execution.
Position-modification failure.
Position-close failure.
EA restart.
VPS restart.
Ambiguous broker responses.
Do not use unlimited retries.

Do not retry an order request unless the implementation can prove that no position or deal was created.

Prohibited Behavior
The EA must never:

Use martingale.
Use grid trading.
Average down.
Add to a losing trade.
Trade without an initial stop-loss.
Round volume upward because the raw volume is below the broker minimum.
Open multiple trades for one signal.
Use the current forming candle for signal confirmation.
Widen a stop-loss after entry.
Increase risk after winning trades.
Automatically modify strategy parameters during a losing period.
Trade when the news filter is unavailable.
Trade when risk cannot be calculated.
Trade when margin safety cannot be verified.
Assume a successful API call means execution succeeded.
Claim that backtest results prove future profitability.
Backtesting Requirements
Use the MT5 Strategy Tester with:

The exact broker symbol when possible.
The broker's actual contract size.
The broker's actual minimum volume and volume step.
Correct account currency.
Correct leverage.
Correct margin mode.
Commissions.
Swaps.
Variable historical spreads.
Real tick data or the most detailed available tick model.
Run at minimum:

Initial deposit: $50
Initial deposit: $100
The test history must include:

Trending markets.
Ranging markets.
High-volatility periods.
Low-volatility periods.
Major news periods.
Different spread conditions.
Different market sessions.
Use chronological validation:

Training period: 60%
Validation period: 20%
Unseen out-of-sample period: 20%
Prefer walk-forward testing.

Do not optimize dozens of parameters.

Only test broad, defensible ranges such as:

ATR stop multiplier: 1.2 to 1.8
Target multiplier: 1.5R to 2.0R
ADX threshold: 18 to 25
Session alternatives: a small number of logical windows
Test parameter neighborhoods. If results work only at highly precise values, document the likely overfitting risk.

Increase assumed spread and slippage by 25% to 50% for robustness testing.

Metrics to Report
Every backtest report must include:

Number of trades.
Net profit after costs.
Profit factor.
Expectancy in R.
Win rate.
Average win in R.
Average loss in R.
Maximum drawdown.
Maximum drawdown duration.
Longest losing streak.
Worst month.
Monthly return distribution.
Average spread paid.
Average slippage.
Commission contribution.
Swap contribution.
Percentage of rejected signals.
Results by day of week.
Results by session.
Results by volatility regime.
Long versus short results.
Results by symbol.
Results after increased cost assumptions.
Number of trades skipped because minimum volume exceeded risk.
Do not evaluate the strategy using net profit alone.

Demo Forward-Test Requirements
Before live deployment, run the EA on a demo account using the intended broker and symbol configuration.

Track at least:

Date and server time
Symbol
Direction
Signal conditions
Planned entry
Actual entry
Stop-loss
Take-profit
Spread
Slippage
Risk in account currency
Result in R
News status
Order status
Error code
Position-management actions
Forward-test for:

At least 8 to 12 weeks
or at least 30 to 50 valid trades
whichever takes longer
Compare forward results with backtest results using:

Trade frequency.
R-multiple results.
Spread.
Slippage.
Commission.
Swap.
Rejected order rate.
Execution latency.
Drawdown.
Losing streaks.
Required Acceptance Criteria
The implementation is complete only when all of the following are true:

The EA compiles in MetaEditor without errors.
All configurable inputs are validated at startup.
The EA uses closed candles for all entry decisions.
No duplicate order can be created for one signal bar.
The EA supports broker-specific symbol specifications.
Lot size is calculated using actual stop distance and OrderCalcProfit().
Volume is rounded downward only.
Trades below the broker minimum are rejected when they exceed risk.
Margin is checked with OrderCalcMargin().
OrderCheck() runs before every order.
The trade-server retcode is inspected after every order.
Initial SL and TP are attached to the order.
Existing positions are reconciled after restart.
Daily loss, weekly loss, and drawdown controls block new entries.
News failure blocks new entries.
Spread failure blocks new entries.
No-trade reasons are written to the log.
Open positions are managed independently of new-entry checks.
Break-even and ATR trailing never worsen the stop.
The time-based exit works after restart.
The EA does not use martingale, grids, or averaging down.
Backtest settings include realistic costs and broker specifications.
A README explains installation, inputs, testing, limitations, and demo-only validation.
Implementation Priorities
When requirements conflict, use this priority order:

Account safety and correct risk calculation.
Broker compatibility and valid order execution.
Closed-candle logic and prevention of look-ahead bias.
Exact strategy rules.
Logging and observability.
Performance and convenience.
When uncertain, reject the trade and log the reason.

Do not silently change strategy rules or risk limits. Any necessary assumption must be documented in the README or an implementation-notes file.

Required Developer Workflow
Before coding:

Inspect the repository structure.
Read existing project instructions and conventions.
Identify the correct MQL5 source and include directories.
Prepare a short implementation plan.
Identify any strategy ambiguity and resolve it conservatively.
During coding:

Implement the modules separately.
Keep broker-specific calculations isolated.
Add defensive validation around all trading operations.
Add structured logging.
Avoid unnecessary dependencies.
Keep the first version focused on one symbol.
After coding:

Compile the EA.
Fix compilation errors and meaningful warnings.
Run static inspection for look-ahead bias and duplicate-entry paths.
Test invalid inputs.
Test insufficient historical data.
Test minimum-volume rejection.
Test invalid-stop rejection.
Test insufficient-margin rejection.
Test news-filter failure.
Test terminal restart and position reconciliation.
Run the required Strategy Tester scenarios.
Update the README and backtest report template.
Final Response Required From the Coding Agent
After implementation, report:

1. Files created or modified
2. Strategy behavior implemented
3. Risk controls implemented
4. Broker-specific calculations implemented
5. Tests and backtests executed
6. Test results
7. Known limitations
8. Assumptions made
9. Any remaining configuration required before demo testing
Do not report tests as passed unless they were actually executed.