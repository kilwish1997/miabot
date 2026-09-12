# H1TrendM15PullbackBreakoutEA

An institutional-grade, low-frequency MetaTrader 5 Expert Advisor designed for capital preservation, systematic trend-pullback execution, and strict defensive risk controls on Gold (`XAUUSD`) and Crypto (`BTCUSD`).

---

## 1. Strategy Architecture & Principles

The EA executes a two-timeframe trend pullback system:
- **Trend Direction (H1):** Evaluated strictly on the latest **closed** H1 candle.
  - **Long:** Fast EMA 50 > Slow EMA 200, Close[1] > EMA 50, ADX(14)[1] >= 20.0.
  - **Short:** Fast EMA 50 < Slow EMA 200, Close[1] < EMA 50, ADX(14)[1] >= 20.0.
- **Pullback Identification (M15):** Shifts 2, 3, or 4 touched or pierced the M15 EMA 20 (`Low <= EMA20` for Long; `High >= EMA20` for Short).
- **Breakout Trigger (M15):** Shift 1 closed beyond shift 2's extreme (`Close[1] > High[2]` for Long; `Close[1] < Low[2]` for Short) and on the correct side of M15 EMA 20.
- **Fail-Closed Design:** If any market data, indicator buffer, broker session check, margin calculation, or safety check is invalid or missing, the EA **rejects the trade and writes the exact reason to structured CSV logs**.

```text
               +-------------------------------------------------+
               |              Closed H1 Candle (Shift 1)         |
               |  EMA50 > EMA200, Close > EMA50, ADX >= 20.0     |
               +-----------------------+-------------------------+
                                       |
                                       v
               +-------------------------------------------------+
               |              M15 Pullback (Shifts 2-4)          |
               |         At least 1 candle touched EMA20         |
               +-----------------------+-------------------------+
                                       |
                                       v
               +-------------------------------------------------+
               |              M15 Breakout (Shift 1)             |
               |    Close[1] > High[2] AND Close[1] > EMA20[1]   |
               +-----------------------+-------------------------+
                                       |
                                       v
               +-------------------------------------------------+
               |     Volatility & Spread Filter Check            |
               |  0.5*Median <= ATR <= 2.0*Median (50-bar lookback)|
               |  Spread <= 10% StopDist AND <= 15% CurrentATR   |
               +-----------------------+-------------------------+
                                       |
                                       v
               +-------------------------------------------------+
               |      OrderCalcProfit() Position Sizing          |
               | Downward volume rounding, Min volume rejection  |
               +-------------------------------------------------+
```

---

## 2. Directory Structure

```text
miabot/
├── MQL5/
│   ├── Experts/
│   │   └── H1TrendM15PullbackBreakoutEA.mq5    # Main EA entry point
│   └── Include/
│       ├── LoggingModule.mqh                  # Structured CSV file logger (19 filter booleans)
│       ├── SessionModule.mqh                  # UTC session window & rollover blackout
│       ├── NewsModule.mqh                     # MT5 Economic Calendar (high-impact USD filter)
│       ├── MarketStructureModule.mqh          # 5-bar swing detection & pullback logic
│       ├── SignalModule.mqh                   # Multi-timeframe indicator handles & median ATR
│       ├── RiskModule.mqh                     # Daily/Weekly loss & persistent HWM kill switch
│       ├── PositionSizingModule.mqh           # OrderCalcProfit sizing & directional normalization
│       ├── ExecutionModule.mqh                # OrderCheck, filling mode negotiation & OrderSend
│       └── PositionManagementModule.mqh      # Break-even (+1.0R), ATR trailing, 12-bar time exit
├── config.example.set                         # Strategy preset for Exness XAUUSD & BTCUSD
├── backtest-report-template.md                # Standardized backtest & forward-test reporting template
└── README.md                                  # Setup, operational guide & parameters
```

---

## 3. Installation & Compilation

### Option A: Windows MetaTrader 5 / MetaEditor
1. Open MT5 and click `File -> Open Data Folder`.
2. Copy the `MQL5` folder from this repository directly into your MT5 data directory.
3. Open **MetaEditor 5** (`F4`).
4. In the Navigator, open `Experts/H1TrendM15PullbackBreakoutEA.mq5` and press **Compile** (`F7`).
5. Confirm compilation finishes with **0 errors and 0 warnings**.

### Option B: Linux Headless / Wine
If running a headless MT5 setup under Wine:
```bash
wine metaeditor64.exe /compile:"Z:\home\kilwish\miabot\MQL5\Experts\H1TrendM15PullbackBreakoutEA.mq5" /log
```
The compiled binary `H1TrendM15PullbackBreakoutEA.ex5` will be created in the `Experts/` folder.

---

## 4. Exness Broker Specifics & UTC Offset

### A. Server Time Offset (`InpBrokerServerUTCOffset = 0`)
* **Exness servers run on UTC+0 (GMT+0) throughout the year.**
* Because Exness does not shift for Daylight Saving Time (DST), `InpBrokerServerUTCOffset` should be kept at `0`.
* The EA automatically maps broker server time directly to the configured UTC trading windows:
  * **Gold (`XAUUSD`):** `08:00` to `16:00` UTC (London + NY overlap).
  * **Crypto (`BTCUSD`):** `07:00` to `20:00` UTC, Monday through Friday.

### B. Symbol Suffix Handling
Exness uses account-dependent symbol suffixes:
* **Standard Account:** `XAUUSDm`, `BTCUSDm`
* **Raw Spread / Zero / Pro Account:** `XAUUSD`, `BTCUSD`
* **Auto-Detection:** By default, leave `InpTradeSymbol = ""` (empty). The EA automatically detects and binds to the active chart symbol (`_Symbol`), ensuring 100% compatibility regardless of suffixes.

---

## 5. Position Sizing & Capital Protection

### A. Broker-Engine Calculation (`OrderCalcProfit`)
* Risk is calculated as a fraction of current account equity (default `0.25%`, hard limit `0.50%`).
* The EA calls `OrderCalcProfit()` directly using the planned entry price and stop-loss price to determine the exact monetary loss of 1.0 lot.
* Commissions and expected slippage buffers are factored into the lot calculation.

### B. Strict Downward Volume Rounding & Min Volume Rejection
* Raw volume is rounded **downward** using `MathFloor` to the broker's `SYMBOL_VOLUME_STEP`.
* **Zero Upward Rounding:** If the calculated raw volume is below the broker's minimum (`SYMBOL_VOLUME_MIN`), the trade is **rejected**.
  * *Example:* On a $100 account with 0.25% risk ($0.25 budget), if the minimum 0.01 lot stop loss would risk $1.20, the trade is rejected.

### C. Directional Price Normalization
* Stop-loss and take-profit prices are normalized to `SYMBOL_TRADE_TICK_SIZE`:
  * **Long Stop-Loss:** Rounded **downward** (away from market).
  * **Short Stop-Loss:** Rounded **upward** (away from market).
  * **Long Take-Profit:** Rounded **upward**.
  * **Short Take-Profit:** Rounded **downward**.

---

## 6. Real-Time Position Management (Every Tick)

Open positions are tracked and managed on **every tick** independently of new signal generation:

1. **Break-Even Adjustment (+1.0R):**
   * When unrealized profit reaches `+1.0R`, the stop-loss is moved to `entryPrice + buffer` (Long) or `entryPrice - buffer` (Short) to cover execution friction.
   * Stop-loss can **never** be widened or moved farther from entry.
2. **ATR Trailing Stop (+1.3R):**
   * When unrealized profit reaches `+1.3R`, trailing stop is activated at `1.5 * M15_ATR(14)`.
   * The trailing stop moves **strictly in the direction of profit** (ratchet mechanism).
3. **Time-Based Exit (12 Completed M15 Bars):**
   * If a trade is neither stopped out nor reaches take-profit after 12 completed M15 bars (3 hours), it is closed at market.
   * Bar count is calculated from server timestamps (`iBarShift`), ensuring it resumes correctly across terminal restarts.

---

## 7. Account Circuit Breakers & Filters

| Filter / Limit | Default Value | Action When Triggered |
| :--- | :--- | :--- |
| **Daily Loss Limit** | `1.0%` of day-start equity | Blocks all new entries for the remainder of the broker day. |
| **Max Daily Losses** | `2` losing trades / day | Blocks all new entries for the remainder of the broker day. |
| **Weekly Loss Limit**| `3.0%` of week-start equity | Blocks all new entries until next Monday 00:00 server time. |
| **Drawdown Kill Switch** | `5.0%` from High-Water Mark | Blocks all new entries until account equity recovers. Persistent in MT5 `GlobalVariable`. |
| **Economic Calendar** | +/- 30 mins around High-Impact USD events | Blocks new entries. (Bypassed in Strategy Tester via `InpNewsFilterInTester=false`). |
| **Spread Filter** | `<= 10% StopDist` AND `<= 15% CurrentATR` | Rejects trade if spread is unusually wide or volatile. |
| **Price Distance** | `<= 0.25 * CurrentATR` from signal close | Rejects trade if market gapped or drifted before execution tick. |

---

## 8. Structured CSV Logging

Every evaluation cycle, rejected signal, order placement, and exit is logged to a structured CSV file located in your MT5 data folder:
`MQL5/Files/H1TrendM15PullbackBreakoutEA_<Symbol>_<Magic>.csv`

### Logged Fields (63 Columns):
- **Timestamps:** Local Time, Server Time, UTC Time.
- **Identification:** Masked Account (`***1234`), Symbol, Magic Number.
- **Signal & Prices:** Direction, H1 EMA50, H1 EMA200, H1 ADX, M15 EMA20, Current ATR, Median ATR, Spread, Signal Close, Entry Price, SL, TP, Stop Distance.
- **Sizing & Risk:** Risk %, Risk $, Raw Volume, Final Volume, Min Volume, Volume Step, Estimated Margin, Daily/Weekly/Drawdown Status strings.
- **19 Boolean Filters:** `ConnectionOK`, `DataOK`, `SessionOK`, `ExposureOK`, `DailyLossOK`, `WeeklyLossOK`, `DrawdownOK`, `NewsOK`, `TrendOK`, `PullbackOK`, `BreakoutOK`, `VolatilityOK`, `SpreadOK`, `PriceDistanceOK`, `StopOK`, `RiskOK`, `VolumeOK`, `MarginOK`, `OrderCheckOK`.
- **Execution & Exits:** Rejection Reason, Retcode, Deal Ticket, Position Ticket, Actual Price, Slippage, Exit Price, Exit Reason, PnL ($), Result (R).

---

## 9. Parameter Reference

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `InpTradeSymbol` | string | `""` | Specific symbol. Leave empty for chart symbol. |
| `InpMagicNumber` | ulong | `108151` | Unique magic identifier for this strategy instance. |
| `InpRiskPercent` | double | `0.25` | Risk percentage per trade (Clamped to max 0.50%). |
| `InpAllowLiveTrading` | bool | `false` | Master safety switch. Must be set to `true` for live execution. |
| `InpH1FastEMA` | int | `50` | Fast trend filter period on H1. |
| `InpH1SlowEMA` | int | `200` | Slow trend filter period on H1. |
| `InpH1ADXPeriod` | int | `14` | ADX period on H1. |
| `InpMinADX` | double | `20.0` | Minimum ADX required for trend qualification. |
| `InpM15PullbackEMA` | int | `20` | Dynamic support/resistance EMA on M15. |
| `InpM15ATRPeriod` | int | `14` | ATR period for volatility and stops. |
| `InpATRLookbackBars` | int | `50` | Number of completed M15 bars used for median ATR. |
| `InpBrokerServerUTCOffset` | int | `0` | Broker server offset from UTC in hours (Exness = 0). |
| `InpStartHourUTC` | int | `8` | UTC session start hour. |
| `InpEndHourUTC` | int | `16` | UTC session end hour. |
| `InpTPMultiplier` | double | `1.8` | Target multiplier in R (Take-Profit = Entry +/- 1.8 * StopDist). |
| `InpEnableNewsFilter` | bool | `true` | MT5 Economic Calendar high-impact filter. |
| `InpNewsFilterInTester` | bool | `false` | Set to `true` only if custom calendar data is loaded in tester. |

---

## 10. Backtesting & Forward-Testing Guidelines

1. **Backtesting (MT5 Strategy Tester):**
   - Use `config.example.set`.
   - Set Model to **"Every tick based on real ticks"**.
   - Ensure `InpNewsFilterInTester=false` so the tester does not reject signals due to lack of historical calendar data.
   - Run tests on both $50 and $100 initial deposit to verify minimum volume rejection behavior.
2. **Demo Forward-Testing:**
   - Attach to an Exness Demo chart (`XAUUSD` or `XAUUSDm`) on the **M15 timeframe**.
   - Enable `InpAllowLiveTrading=true` and enable **Algo Trading** in the MT5 toolbar.
   - Forward test for at least **8 to 12 weeks** or **30 to 50 completed trades** before any live consideration.
   - Inspect `MQL5/Files/` regularly to review the generated CSV logs.

---

## 11. Risk Disclaimer

This software is developed strictly for research, algorithmic backtesting, and demo validation. Trading foreign exchange, precious metals, and cryptocurrencies carries high risk and may not be suitable for all investors. Past performance in backtests does not guarantee future results. Never risk capital you cannot afford to lose.
# miabot
