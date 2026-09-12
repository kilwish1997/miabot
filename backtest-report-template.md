# Backtest & Forward-Test Report Template: H1TrendM15PullbackBreakoutEA

## 1. Test Overview

- **Strategy Name:** H1TrendM15PullbackBreakoutEA (Institutional Edition)
- **Symbol / Ticker:** `XAUUSD` / `XAUUSDm` (or `BTCUSD`)
- **Broker:** Exness
- **Account Type:** Standard / Raw Spread / Pro
- **Account Currency:** USD
- **Initial Deposit:** $50 / $100 / $1,000
- **Test Period:** [YYYY.MM.DD] to [YYYY.MM.DD]
- **Timeframes:** Trend = H1, Entry = M15
- **Tick Model:** Every tick based on real ticks (100% History Quality)
- **Execution Mode:** Random delay / 10-50ms latency simulated
- **Session Configuration:** London Open (08:00–12:00 UTC) & London/NY Overlap (12:00–16:00 UTC)
- **News Filter Mode:** Tier 1 Core Macro Events (FOMC, CPI, NFP, Fed Rate Decisions)

---

## 2. Walk-Forward Validation (In-Sample vs Out-of-Sample)

| Metric | In-Sample (2021–2023) | Out-of-Sample (2024–Present) | Target Threshold | Degradation / Status |
| :--- | :--- | :--- | :--- | :--- |
| **Total Net Profit** | $0.00 | $0.00 | > 0 | [Pass/Fail] |
| **Profit Factor** | 0.00 | 0.00 | >= 1.50 (IS) / >= 1.25 (OOS) | Degradation <= 25% |
| **Total Closed Trades** | 0 | 0 | >= 30 | [Pass/Fail] |
| **Trade Frequency** | 0 trades/month | 0 trades/month | 3 – 8 trades / month | [Pass/Fail] |
| **Win Rate (%)** | 0.00% | 0.00% | >= 40.0% (at 1:1.8 RR) | [Pass/Fail] |
| **Expectancy (in R)** | +0.00 R | +0.00 R | >= +0.25 R | [Pass/Fail] |
| **Average Win (in R)** | +0.00 R | +0.00 R | >= +1.50 R | [Pass/Fail] |
| **Average Loss (in R)** | -0.00 R | -0.00 R | <= -1.00 R | [Pass/Fail] |
| **Max Equity Drawdown (%)**| 0.00% | 0.00% | <= 5.00% | [Pass/Fail] |
| **Max Drawdown Duration** | 0 days | 0 days | < 30 days | [Pass/Fail] |
| **Max Consecutive Losses**| 0 trades | 0 trades | <= 4 trades | [Pass/Fail] |
| **Worst Monthly Return** | 0.00% | 0.00% | > -3.00% | [Pass/Fail] |

---

## 3. Slippage Stress Testing (Robustness Audit)

Verify that the system's edge does not dissolve under real-world slippage:

| Scenario | Profit Factor | Net Profit ($) | Win Rate (%) | Max Drawdown (%) | Edge Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Baseline (0 Pips Added)** | 0.00 | $0.00 | 0.0% | 0.00% | Benchmark |
| **+2 Pips Adverse Slippage** | 0.00 | $0.00 | 0.0% | 0.00% | Robust / Sensitive |
| **+5 Pips Adverse Slippage** | 0.00 | $0.00 | 0.0% | 0.00% | Survives / Failed |

*Rule:* If the system becomes unprofitable with 2–5 pips of adverse slippage, the edge is too thin and cannot survive live spreads.

---

## 4. Tier-1 News Filter Impact Comparison

Quantify the exact contribution of the economic calendar blackout filter:

| Configuration | Total Trades | Profit Factor | Net Profit ($) | Max Drawdown (%) | Win Rate (%) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **With Tier-1 Filter (FOMC/CPI/NFP)** | 0 | 0.00 | $0.00 | 0.00% | 0.0% |
| **Without News Filter (All Allowed)** | 0 | 0.00 | $0.00 | 0.00% | 0.0% |
| **Filter Net Contribution** | Δ 0 | Δ 0.00 | Δ $0.00 | Δ 0.00% | Δ 0.0% |

---

## 5. Cost & Friction Contribution

| Cost Component | Total Amount ($) | % Contribution of Gross Profit | Notes |
| :--- | :--- | :--- | :--- |
| **Commissions Paid** | $0.00 | 0.0% | ECN commission ($/lot) |
| **Swaps Paid** | $0.00 | 0.0% | Overnight financing |
| **Average Spread Paid** | 0.00 pts | - | Average bid/ask spread |
| **Average Slippage** | 0.00 pts | - | Execution drift |

---

## 6. Signal Filter & Rejection Statistics (Funnel Analysis)

Extracted directly from `PrintRejectionSummary()` in the EA log:

| Evaluation Filter | Total Evaluations | Signals Rejected | Rejection Rate (%) | Target Diagnostic |
| :--- | :--- | :--- | :--- | :--- |
| **Session Filter (UTC Window / Rollover)** | 0 | 0 | 0.0% | Primary filter (normal > 50%) |
| **Exposure / Open Position Block** | 0 | 0 | 0.0% | Blocks duplicate trades |
| **Cooldown Active (1 M15 Bar)** | 0 | 0 | 0.0% | Prevents revenge trading |
| **Daily / Weekly / Drawdown Limits** | 0 | 0 | 0.0% | Fail-closed circuit breakers |
| **High-Impact News Blackout** | 0 | 0 | 0.0% | Blackouts before/after releases |
| **H1 Trend Filter (EMA/ADX/DMI)** | 0 | 0 | 0.0% | Trend regime alignment |
| **M15 Pullback Condition (Zone + Rejection)**| 0 | 0 | 0.0% | Healthy structural pullback |
| **M15 Breakout Quality & Retest** | 0 | 0 | 0.0% | Breakout distance / CLV |
| **Volatility Filter (0.5x - 2.0x Median ATR)**| 0 | 0 | 0.0% | Rejects dead/erratic volatility |
| **Spread Filter (<=10% Stop, <=15% ATR)** | 0 | 0 | 0.0% | Wide spread protection |
| **Asymmetric Price Drift Filter** | 0 | 0 | 0.0% | Adverse drift <= 0.20 ATR |
| **Volume / Margin / OrderCheck** | 0 | 0 | 0.0% | Broker execution safety |
| **Total Executed Trades** | **0** | - | **0.0%** | **Target: 3–8 trades/month** |

---

## 7. Regime Breakdown

### A. Long vs. Short Results
- **Long Trades:** 0 | Win Rate: 0.0% | Profit Factor: 0.00 | Total PnL: $0.00
- **Short Trades:** 0 | Win Rate: 0.0% | Profit Factor: 0.00 | Total PnL: $0.00

### B. Results by Volatility Regime (ATR vs Median ATR)
- **Low Volatility (0.5x - 0.9x Median):** 0 trades | Profit Factor: 0.00
- **Normal Volatility (0.9x - 1.4x Median):** 0 trades | Profit Factor: 0.00
- **Elevated Volatility (1.4x - 2.0x Median):** 0 trades | Profit Factor: 0.00

### C. Results by Day of Week
- **Monday:** 0 trades | PnL: $0.00
- **Tuesday:** 0 trades | PnL: $0.00
- **Wednesday:** 0 trades | PnL: $0.00
- **Thursday:** 0 trades | PnL: $0.00
- **Friday:** 0 trades | PnL: $0.00

---

## 8. Live / Demo Forward-Test Comparison (8-12 Weeks)

| Metric | Backtest (Chronological OOS) | Demo Forward-Test (8-12 Weeks) | Discrepancy (%) | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Trade Frequency** | 0 trades / month | 0 trades / month | 0.0% | [Aligned/Divergent] |
| **Average R-Multiple** | +0.00 R | +0.00 R | 0.00 R | [Aligned/Divergent] |
| **Win Rate** | 0.0% | 0.0% | 0.0% | [Aligned/Divergent] |
| **Average Slippage** | 0.0 pts | 0.0 pts | 0.0 pts | [Aligned/Divergent] |
| **Order Rejection Rate** | 0.0% | 0.0% | 0.0% | [Aligned/Divergent] |
