# Principal-Protected Barbell Option Vault (On-Chain RWA & Off-Chain Brokerage API)

An institutional-grade, quantitative **Barbell Portfolio** engine that pairs **100% principal custody in short-duration US Treasury bills** with **Google TimesFM 3.0 AI-forecasted Bull Call Spreads**—implementable either **On-Chain (ERC-4626 RWA Vault + Hyperliquid L1)** or **Off-Chain (Robinhood / Alpaca / IBKR API + `SGOV` + CBOE Options)**.

---

## 🌟 Executive Summary & Dual-Track Architecture

Following Nassim Taleb's *Barbell Strategy*, this repo automates a "ratcheting" principal floor:
* **100% Principal Protection**: 100% of base capital is held in short-duration US Treasury vehicles (`Sky sUSDS` / `Circle USYC` / `Ondo USDY` on-chain, or `SGOV` / `BOXX` ETFs in a brokerage account) earning ~4.70% APY.
* **Yield-in-Arrears Option Budget**: The engine **never risks deposited principal**. It skims *only* newly accrued monthly T-Bill interest above `protectedPrincipalUSD`.
* **Google TimesFM 3.0 AI Regime Filter**: A foundation time-series model evaluates 20-day forward kinetic drift and realized volatility before every monthly epoch. During bear markets or volatility panics, zero options are bought and 100% of T-Bill yield compounds in cash.
* **High-Water-Mark Ratchet Compounding**: Winning option payouts are swept back into the US Treasury reserve and **permanently added to the protected principal floor**, locking in gains forever.

### Which Track Should You Run? (On-Chain vs. Traditional Broker API)

| Dimension | Track 1: On-Chain Vault (`vault_execution_bot.py`) | Track 2: Off-Chain Broker API (`broker_barbell_bot.py`) |
| :--- | :--- | :--- |
| **Best Use Case** | **Scaling a DeFi Protocol / Managing External TVL** (Earn 15% performance fees via smart contract) | **Compounding Personal / Proprietary Capital** (Zero smart-contract risk, SIPC insured) |
| **Safe Base Asset** | `Sky sUSDS`, `Circle USYC`, or `Ondo USDY` (ERC-4626) | **`SGOV`** (iShares 0-3 Month T-Bill ETF) or **`BOXX`** |
| **Option Execution Venue** | Hyperliquid L1 / Derive (Lyra) on-chain derivatives | **Robinhood (`robin_stocks`)**, **Alpaca (`OrderClass.MLEG`)**, or **IBKR** (CBOE Options) |
| **Bid-Ask Slippage Drag** | **Higher (5%–15% of option premium)** on thinner on-chain books | **Ultra-Low (~1.5%–2.5% of premium)** on penny-wide CBOE `QQQ` / `GLD` / `IBIT` books |
| **Contract Granularity** | **Fractional (`0.0001` units)** — 100% of monthly interest deployed | **100-Share Standard Lots** — leftover dividend change auto-reinvested into fractional `SGOV` |

---

## 🏗 System Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────────┐
│                        DUAL-TRACK AUTONOMOUS BARBELL EXECUTION PIPELINE                        │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
                                                │
   1. Base Treasury Custody (100% Floor)        ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ • On-Chain Track: PrincipalProtectedRWAVault.sol holds Sky sUSDS / USYC (4.70% APY)      │
  │ • Broker Track:   Brokerage account holds SGOV (0-3 Mo T-Bill ETF, pays monthly cash div)│
  │ • Invariant:      Base principal ($100,000) is NEVER touched for option purchases!       │
  └─────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                │
   2. Quantitative AI Signal Engine             ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ Google TimesFM 3.0 Foundation Forecaster                                                 │
  │ • Analyzes 60-day rolling lookback of target asset (QQQ, GLD, IBIT, BTC, ETH)            │
  │ • Forecasts 20-day forward kinetic price trajectory & checks 21d realized volatility cap │
  │ • Decisions:                                                                             │
  │     - BULLISH_DEPLOY    ==> Skim monthly T-Bill dividend & buy Bull Call Spread          │
  │     - RISK_OFF_PRESERVE ==> Buy zero options; reinvest 100% of dividend into T-Bills     │
  └─────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                │
   3. Execution Layer (On-Chain OR CBOE)        ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ • Track 1 (On-Chain): Hyperliquid L1 API Bridge (fractional synthetic/option spread)     │
  │ • Track 2 (Broker):   Robinhood (`order_buy_option_spread`) or Alpaca (`OrderClass.MLEG`)│
  │   Constructs atomic 2-leg Bull Call Spread (e.g., Buy QQQ $700 Call / Sell $705 Call)    │
  │   and reinvests any leftover unspent dividend change straight back into SGOV shares.     │
  └─────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                │
   4. High-Water-Mark Settlement Ratchet        ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ Epoch Settlement & Principal Ratchet Loop                                                │
  │ • Winning option payouts are swept back into sUSDS (On-Chain) or SGOV shares (Broker)    │
  │ • ==> PERMANENTLY RATCHETS UP PROTECTED PRINCIPAL FLOOR!                                 │
  └──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Idealized Backtest Results (2021–2026) & Real-World Slippage Tradeoffs

Simulated across the full **2021–2026 market cycle** (including the **2022 bear market** where Nasdaq `QQQ` fell **-33%** and `BTC` fell **-75%**) starting from **$100,000 USD**:

| Strategy (Idealized Backtest) | Initial Deposit | Final NAV | Total Return | Idealized APY | Annual Vol | **Max Principal Drawdown** | Avg Option Gearing |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| *Baseline: Plain T-Bills (4.70%)* | $100,000 | $126,820 | +26.8% | 4.70% | 0.00% | 0.00% | 0.00x |
| **Barbell 1: T-Bills + Gold (`GLD`) Pure Skim** | $100,000 | **$131,304** | **+31.3%** | **5.41%** | 1.27% | **0.00%** | 0.55x |
| **Barbell 2: T-Bills + Nasdaq (`QQQ`) Pure Skim**| $100,000 | **$131,302** | **+31.3%** | **5.41%** | 1.51% | **0.00%** | 0.53x |
| **Barbell 3: T-Bills + `QQQ` Collar-Boosted**    | $100,000 | **$132,993** | **+33.0%** | **5.67%** | 1.55% | **0.00%** | 0.40x |
| **Barbell 4: T-Bills + `BTC` Collar-Boosted**    | $100,000 | **$130,074** | **+30.1%** | **5.14%** | 1.50% | **0.00%** | 0.28x |

---

### ⚠️ Reality Check: Idealized Backtest vs. Live Trading Slippage

> **Important Quantitative Disclaimer**: The table above represents an **idealized theoretical backtest** priced using Black-Scholes with continuous fractional contract sizing. Any real-world deployment faces four concrete execution frictions that reduce realized APY:

1. **Multi-Leg Bid-Ask Slippage (Why CBOE Beats On-Chain for Personal Capital)**:
   * **On-Chain Options Problem**: Crossing the bid-ask spread on two legs (buying $K_{\text{long}}$ and selling $K_{\text{short}}$) on thinner on-chain option books typically costs **5% to 15% of the option premium** in slippage. Because your monthly option budget is ~0.39% of AUM, a 10% premium slippage shaves **~40 to 60 bps off your annual APY**.
   * **The Brokerage API Fix (`broker_barbell_bot.py`)**: By executing on ultra-liquid CBOE penny-pilot ETFs (`QQQ`, `SPY`, `GLD`, `IBIT`), bid-ask spreads are **$0.01 to $0.03 per leg** (~$0.04/sh on a $2.21 spread = **only ~1.78% premium drag**, or <10 bps/yr).
2. **The 100-Share Lot-Size Granularity Constraint**:
   * On-chain simulation assumes you can spend exactly $391.67 to buy `0.4082` contracts. In US equity options, 1 contract = **100 shares**, meaning a $5-wide `QQQ` call spread costs **$225.00** per contract.
   * **How `broker_barbell_bot.py` handles this**: The bot dynamically selects the optimal strike width ($1 to $15 wide) so `cost_per_contract <= monthly_dividend`, buys an integer number of spreads (e.g., 1x `QQQ` $700/$705 Call Spread for $225.00), and **immediately sweeps the remaining $166.67 into fractional `SGOV` shares** so zero cash sits idle. For smaller accounts (<$50k), the bot automatically falls back to lower-priced liquid ETFs like **`IBIT`** (~$44/sh, where 1 spread costs only ~$35–$60).
3. **Dynamic Volatility Skew & Pin Risk at Expiration**:
   * During rapid breakout rallies, market makers widen OTM call implied volatility. Furthermore, if the ETF closes between $K_{\text{long}}$ and $K_{\text{short}}$ on expiration Friday, you must close the spread 15–30 minutes before the 4:00 PM ET bell to avoid weekend pin/assignment risk (costing an extra $0.02–$0.04/sh in exit slippage).
4. **Interest-Rate Cyclicality**:
   * The backtest holds T-Bill yield constant at 4.70% to isolate option overlay performance. If short-term Fed rates fall to 2.5%, your monthly pure-skim option budget shrinks proportionally.

---

## 📁 Repository Structure

```
rwa-option-vault/
├── PrincipalProtectedRWAVault.sol   # Track 1: Production Solidity ERC-4626 smart contract
├── vault_execution_bot.py           # Track 1: On-Chain bot (TimesFM 3.0 + Hyperliquid L1 bridge)
├── broker_barbell_bot.py            # Track 2: Off-Chain Broker bot (Robinhood / Alpaca / Paper + SGOV + CBOE)
├── simulate_solution_a_vault.py     # Full 5-year quantitative backtester & dashboard generator
├── solution_a_backtest_summary.csv  # Granular backtest performance statistics
├── solution_a_vault_dashboard.png   # 4-panel performance & principal ratchet visualization
├── vault_state.json                 # Persistent state for Track 1 (On-Chain)
├── broker_barbell_state.json        # Persistent state for Track 2 (Brokerage SGOV + CBOE)
├── requirements.txt                 # Python dependencies
└── README.md                        # Documentation, architecture, & slippage analysis
```

---

## 🚀 Quickstart & CLI Usage

### 1. Installation

```bash
git clone git@github.com:fredLuv/rwa-option-vault.git
cd rwa-option-vault

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Track 2: Off-Chain Brokerage Bot (`SGOV` + CBOE Options via Paper / Robinhood / Alpaca)

```bash
# Run in safe Paper Mode on QQQ (models real CBOE 100-share lot sizing & $0.04/sh slippage):
python broker_barbell_bot.py --broker paper --symbol QQQ

# Run on Gold (GLD) or BlackRock Bitcoin ETF (IBIT):
python broker_barbell_bot.py --broker paper --symbol GLD
python broker_barbell_bot.py --broker paper --symbol IBIT

# Execute live on Robinhood (requires `pip install robin_stocks pyotp` + env vars RH_USERNAME, RH_PASSWORD, RH_TOTP_SECRET):
python broker_barbell_bot.py --broker robinhood --symbol QQQ

# Execute on Alpaca Multi-Leg Options API (requires env vars ALPACA_API_KEY, ALPACA_SECRET_KEY):
python broker_barbell_bot.py --broker alpaca --symbol QQQ
```

### 3. Track 1: On-Chain RWA Vault Bot (Hyperliquid L1 + `PrincipalProtectedRWAVault.sol`)

```bash
# Check live vault status:
python vault_execution_bot.py --action status

# Run monthly epoch with TimesFM 3.0 signal on BTC, ETH, or SOL:
python vault_execution_bot.py --action run_epoch --asset BTC

# Settle active epoch and ratchet up principal floor:
python vault_execution_bot.py --action settle --asset BTC

# Run end-to-end live simulation demo:
python vault_execution_bot.py --action simulate_demo --asset BTC
```

---

## 📄 License
MIT License. Created by [fredLuv](https://github.com/fredLuv).
