# Conservative Scalper EA — MT4

A disciplined, rule-based MT4 Expert Advisor for conservative intraday scalping on major FX pairs. Capital preservation is the top priority. No martingale, no grid, no averaging into losers.

---

## Strategy Overview

| Layer | Logic |
|---|---|
| **Bias filter** | M15 EMA 50 vs EMA 200 — long bias when fast > slow (and rising), short bias when fast < slow (and falling) |
| **Execution filter** | M5 EMA 20 — price must be above EMA for longs, below for shorts |
| **Momentum trigger** | RSI 14 crosses above 50 (long) or below 50 (short) |
| **Entry confirm** | Current bar closes above prior bar high (long) or below prior bar low (short) |
| **Trade filters** | Spread cap, ATR minimum, session hours, day-of-week, rollover block, one trade per symbol, total open risk cap |

---

## Risk Management

- Fixed-fractional sizing: risk a set **% of equity** per trade (default **0.25%**)
- Hard stop loss + hard take profit on **every** trade
- No martingale, no grid, no averaging
- Break-even logic (optional, default on)
- Trailing stop (optional, default off)
- Time-based exit for stalled trades (default 20 min)
- Session-end close option

### Daily Guardrails

| Limit | Default |
|---|---|
| Max trades per day | 6 |
| Max daily loss | 1.5% |
| Max consecutive losses | 3 (pause) |
| Max equity drawdown (hard stop) | 8% |
| Max total open risk | 1.0% |

---

## Recommended Settings

### EURUSD M5

```
BiasTimeframe     = M15
BiasFastEMA       = 50
BiasSlowEMA       = 200
ExecEMA_Period    = 20
RSI_Period        = 14
ATR_Period        = 14
MinATR_Pips       = 3.0
MaxSpreadPips     = 1.5
StopLossMode      = 1   (ATR)
StopLossATRMult   = 1.2
TakeProfitMode    = 1   (ATR)
TakeProfitATRMult = 1.2
RiskPercent       = 0.50
MaxDrawdownPercent= 20.0
MaxDailyLossPercent = 2.0
SessionStartHour  = 8
SessionEndHour    = 17
UseBreakEven      = true
BreakEvenTriggerR = 0.8
UseTimeExit       = true
MaxTradeMinutes   = 20
AllowFriday       = false
```

### GBPUSD M5

```
BiasTimeframe     = M15
BiasFastEMA       = 50
BiasSlowEMA       = 200
ExecEMA_Period    = 20
RSI_Period        = 14
ATR_Period        = 14
MinATR_Pips       = 4.0
MaxSpreadPips     = 2.0
StopLossMode      = 1   (ATR)
StopLossATRMult   = 1.4
TakeProfitMode    = 1   (ATR)
TakeProfitATRMult = 1.4
RiskPercent       = 0.50
MaxDrawdownPercent= 20.0
MaxDailyLossPercent = 2.0
SessionStartHour  = 8
SessionEndHour    = 17
UseBreakEven      = true
BreakEvenTriggerR = 0.8
UseTimeExit       = true
MaxTradeMinutes   = 25
AllowFriday       = false
```

> GBPUSD is more volatile — slightly wider ATR multipliers and longer time exit are recommended.

### USDJPY M5 — increase MaxSpreadPips to 2.0, MinATR_Pips to 4.0

---

## Performance Targets

| Metric | Target |
|---|---|
| Win rate | 55–60% |
| Reward : Risk | 1.0 to 1.2 |
| Profit factor | 1.3 to 1.6 |
| Max drawdown | < 20% (hard cutoff) |
| Monthly return | 4–8% at 0.5% risk/trade |

> **Note:** No EA can guarantee profits. These are design targets for a conservative system tested across varied market conditions. Past backtest results do not guarantee future performance.

---

## Broker Requirements

- MT4 platform (build 600+)
- Low spread on EURUSD: ideally < 1.0 pip raw/ECN spread
- Fast execution (STP/ECN preferred over dealing desk)
- Supports 4-digit or 5-digit pricing — EA handles both automatically
- NFA/FIFO compliant brokers supported (one trade per symbol mode)

---

## Installation

1. Copy `ConservativeScalper.mq4` to your MT4 `MQL4/Experts/` folder
2. Open MetaEditor → compile → confirm no errors
3. Attach to an **M5** EURUSD (or other pair) chart
4. Enable **Allow automated trading** and **Allow DLL imports** if required
5. Set `MagicNumber` to a unique value if running multiple instances

---

## Backtesting

- Use **Strategy Tester** in MT4
- Select **Every tick** model for best accuracy
- Enable **Use date** to limit range
- Start with default inputs, then optimize in small increments
- Validate on out-of-sample period before going live

Key metrics to review: profit factor, max drawdown, trade count, expectancy, average trade duration.

---

## Risks & Limitations

- Scalping EAs are sensitive to spread and execution quality — results vary by broker
- Strategy may underperform in strong trending or choppy, ranging markets
- Requires a stable VPS for 24/5 operation
- Backtest quality depends on tick data quality; prefer 99% modelling quality data
- RSI + EMA signals can produce false positives in low-volume periods
- No news filter is built in — manually disable the EA before high-impact news events using the `AllowNewTrades = false` input

---

## Input Reference

| Input | Default | Description |
|---|---|---|
| `MagicNumber` | 20260409 | Unique order identifier |
| `TradeComment` | CScalp | Order comment |
| `EnableLong` | true | Allow buy trades |
| `EnableShort` | true | Allow sell trades |
| `OneTradePerSymbol` | true | Prevent stacking |
| `AllowNewTrades` | true | Master on/off |
| `SessionStartHour` | 8 | Server hour to start |
| `SessionEndHour` | 17 | Server hour to stop |
| `AllowFriday` | false | Skip thin Friday close |
| `RolloverBlockBefore` | 30 | Mins before 00:00 server |
| `RolloverBlockAfter` | 30 | Mins after 00:00 server |
| `BiasTimeframe` | M15 | Trend filter TF |
| `BiasFastEMA` | 50 | Trend fast EMA |
| `BiasSlowEMA` | 200 | Trend slow EMA |
| `ExecEMA_Period` | 20 | Local direction EMA |
| `RSI_Period` | 14 | RSI period |
| `MinATR_Pips` | 3.0 | Min ATR — skip dead market |
| `MaxSpreadPips` | 1.5 | Max allowed spread |
| `MaxSlippagePts` | 3 | Max allowed slippage |
| `LotSizingMode` | 1 | 0=Fixed 1=Risk% |
| `RiskPercent` | 0.25 | % equity per trade |
| `StopLossMode` | 1 | 0=Pips 1=ATR mult |
| `StopLossATRMult` | 1.2 | ATR multiplier for SL |
| `TakeProfitATRMult` | 1.2 | ATR multiplier for TP |
| `UseBreakEven` | true | Enable BE logic |
| `BreakEvenTriggerR` | 0.8 | Move BE after 0.8R |
| `UseTrailingStop` | false | Enable trail |
| `UseTimeExit` | true | Close stalled trades |
| `MaxTradeMinutes` | 20 | Max trade duration |
| `CloseAtSessionEnd` | true | Close at session end |
| `MaxTradesPerDay` | 6 | Daily trade cap |
| `MaxDailyLossPercent` | 1.5 | Daily loss cap % |
| `MaxConsecutiveLosses` | 3 | Consecutive loss pause |
| `MaxDrawdownPercent` | 8.0 | Hard stop equity DD % |

---

## License

MIT — free to use and modify. No warranty expressed or implied.
<!-- updated: 2025-08-08-r01 -->
