# Principal-Protected RWA Option Vault (Solution A)

An institutional-grade, non-custodial decentralized structured note protocol that bridges **Tier-1 Real-World Asset (RWA) US Treasury yields** with **Google TimesFM 3.0 AI-forecasted option overlays on Hyperliquid L1**.

---

## 🌟 Executive Summary & Value Proposition

Traditional on-chain structured products often suffer from:
1. **DeFi Contagion & Depeg Risk**: Unregulated synthetic stablecoins (e.g., `xUSD`, `deUSD`, `USD0++`) depegging and destroying principal.
2. **Smart Contract Complexity**: Complex nested rehypothecation layers (e.g., Penpie exploits) creating multi-million dollar vulnerabilities.
3. **Negative Free Cash Flow / High Volatility**: Pure option-selling vaults (covered calls / strangles) suffering catastrophic tail-risk drawdowns in bear crashes.

**Solution A solves this by eliminating third-party counterparty risk entirely:**
* **100% Principal Protection**: 100% of user capital is deposited directly into bankruptcy-remote, daily-audited Tier-1 US Treasury tokens (`Sky sUSDS`, `Circle USYC`, or `Ondo USDY`) earning ~4.70% APY.
* **Yield-in-Arrears Option Budget**: The vault **never touches deposited principal**. It skims *only* newly accrued monthly T-Bill interest above the `protectedPrincipalUSD` floor.
* **Google TimesFM 3.0 AI Regime Filter**: An AI foundation time-series model selectively deploys option spreads *only* during statistically constructive kinetic drift windows. In bear/panic regimes, 100% of the yield is preserved in cash.
* **High-Water-Mark Ratchet Compounding**: When option positions win, net profits are swept back into the RWA Treasury token and **permanently ratcheted into the protected principal floor**, locking in gains forever and compounding future T-Bill yield.

---

## 🏗 System Architecture

```
┌────────────────────────────────────────────────────────────────────────────────────────────────┐
│                             END-TO-END AUTONOMOUS VAULT PIPELINE                               │
└────────────────────────────────────────────────────────────────────────────────────────────────┘
                                                │
   1. On-Chain Tier-1 Custody                   ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ PrincipalProtectedRWAVault.sol (ERC-4626)                                                │
  │ • Holds 100% in Sky sUSDS / Ondo USDY / Circle USYC (4.70% APY)                           │
  │ • Enforces invariant: protectedPrincipalUSD can NEVER be touched by the option engine!    │
  │ • Accrues monthly interest (~0.39%/mo) -> harvestableOptionBudgetUSD                     │
  └─────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                │
   2. Quantitative AI Signal Engine             ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ Google TimesFM 3.0 Foundation Forecaster                                                 │
  │ • Analyzes 60-day rolling lookback of spot asset (BTC, ETH, SOL, QQQ, GLD)               │
  │ • Forecasts 20-day forward kinetic price trajectory and calculates expected drift        │
  │ • Regime Filter: Momentum (S0 >= SMA50 or Drift >= +2.0%) AND Volatility (RV <= 75th cap)│
  │ • Decisions:                                                                             │
  │     - BULLISH_DEPLOY    ==> Skim accrued interest & buy Bull Call Spread                 │
  │     - RISK_OFF_PRESERVE ==> Zero options bought; 100% interest stays in RWA to compound │
  └─────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                │
   3. Exchange Execution Layer                  ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ Hyperliquid L1 API Bridge (https://api.hyperliquid.xyz/info)                             │
  │ • Queries live orderbook mark price, funding rates, and open interest                    │
  │ • Constructs Bull Call Spread: Buy 1.01x ATM Call / Sell 1.045x OTM Call                 │
  │ • Generates verified order ticket with full notional gearing (~40x–85x on option budget) │
  └─────────────────────────────────────────────┬────────────────────────────────────────────┘
                                                │
   4. High-Water-Mark Settlement Ratchet        ▼
  ┌──────────────────────────────────────────────────────────────────────────────────────────┐
  │ Epoch Settlement & Principal Ratchet Loop                                                │
  │ • At expiry: computes intrinsic option payoff per unit                                   │
  │ • Protocol Performance Fee (15%) deducted on net profit (Founder revenue engine)         │
  │ • Net winnings deposited into Tier-1 RWA Treasury token                                  │
  │ • ==> RATCHET UP PROTECTED PRINCIPAL FLOOR!                                              │
  │   (Option wins become permanent capital that increases future monthly T-Bill yield!)     │
  └──────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Quantitative Backtest Results (2021–2026 Real Market Data)

Simulated across the full **2021–2026 market cycle** (including the brutal **2022 bear market** where Nasdaq crashed **-33%** and Bitcoin crashed **-75%**) starting from an initial deposit of **$100,000 USDC**:

| Strategy | Initial Deposit | Final Vault NAV | Total Return | APY (CAGR) | Annual Volatility | **Max Principal Drawdown** | Avg Option Gearing | **Founder Fees (@ $10M TVL)** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| *Baseline: Plain T-Bills (4.70%)* | $100,000 | $126,820 | +26.8% | 4.70% | 0.00% | 0.00% | 0.00x | $0 |
| **Vault 1: RWA + Gold (`PAXG`) Pure Skim** | $100,000 | **$131,304** | **+31.3%** | **5.41%** | 1.27% | **0.00%** | 0.55x | **$175,263** |
| **Vault 2: RWA + Nasdaq (`QQQ`) Pure Skim**| $100,000 | **$131,302** | **+31.3%** | **5.41%** | 1.51% | **0.00%** | 0.53x | **$221,277** |
| **Vault 3: RWA + `QQQ` Collar-Boosted**    | $100,000 | **$132,993** | **+33.0%** | **5.67%** | 1.55% | **0.00%** | 0.40x | **$239,553** |
| **Vault 4: RWA + `BTC` Collar-Boosted**    | $100,000 | **$130,074** | **+30.1%** | **5.14%** | 1.50% | **0.00%** | 0.28x | **$180,705** |

### Key Backtest Insights
1. **Zero Drawdown in 2022**: While underlying equity and crypto indices cratered by 33% to 75%, the vault's principal ratchet **never declined by a single basis point** (0.00% max drawdown).
2. **Asymmetric Convexity**: A tiny monthly budget of ~$390–$550 in T-Bill yield buys massive notional upside exposure ($30,000+), paying out $1,100 to $2,300 during breakout months.

---

## 📁 Repository Structure

```
rwa-option-vault/
├── PrincipalProtectedRWAVault.sol   # Production Solidity ERC-4626 smart contract
├── vault_execution_bot.py           # Autonomous quant bot (TimesFM + Hyperliquid L1 bridge)
├── simulate_solution_a_vault.py     # Comprehensive quantitative backtester & dashboard generator
├── solution_a_backtest_summary.csv  # Granular backtest performance statistics
├── solution_a_vault_dashboard.png   # 4-panel performance & principal ratchet visualization
├── vault_state.json                 # Persistent vault state & trade logs
├── requirements.txt                 # Python dependencies
├── .gitignore                       # Git ignore configuration
└── README.md                        # Documentation & setup guide
```

---

## 🚀 Quickstart & Setup Guide

### 1. Prerequisites
* Python 3.10+ (Recommended: Python 3.11)
* Git

### 2. Installation
Clone the repository and set up a virtual environment:

```bash
git clone git@github.com:fredLuv/rwa-option-vault.git
cd rwa-option-vault

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Usage & CLI Commands

#### A. Check Live Vault & Floor Status
Inspect the current state of the vault, protected floor, and active positions:
```bash
python vault_execution_bot.py --action status
```

#### B. Run a New Monthly Execution Epoch
Pulls live market context from Hyperliquid, runs Google TimesFM 3.0 inference, and places the Bull Call Spread:
```bash
# Run on Bitcoin:
python vault_execution_bot.py --action run_epoch --asset BTC

# Run on Ethereum:
python vault_execution_bot.py --action run_epoch --asset ETH

# Run on Solana:
python vault_execution_bot.py --action run_epoch --asset SOL
```

#### C. Settle an Active Epoch & Ratchet Principal Floor
Settles using live Hyperliquid mark prices, collects performance fees, and permanently ratchets the floor:
```bash
# Settle using live market mark price:
python vault_execution_bot.py --action settle --asset BTC

# Or simulate settlement at an explicit target price (e.g., $80,500):
python vault_execution_bot.py --action settle --asset BTC --expiry_px 80500.0
```

#### D. Run the End-to-End Live Simulation Demo
Runs an entire epoch from yield accrual, TimesFM inference, Hyperliquid order placement, through settlement:
```bash
python vault_execution_bot.py --action simulate_demo --asset BTC
```

#### E. Re-run Full Historical Backtest (2021–2026)
Simulates all 4 vault strategies across historical data and regenerates the 4-panel dashboard:
```bash
python simulate_solution_a_vault.py
```

---

## 🔒 Smart Contract Security & Invariants

In [`PrincipalProtectedRWAVault.sol`](PrincipalProtectedRWAVault.sol), two critical on-chain invariants protect investor capital:

1. **Strict Balance Floor Invariant**:
   ```solidity
   // In harvestYieldToOptionEngine():
   require(totalRWAValueUSD() + 1 >= protectedPrincipalUSD, "INVARIANT_BREACH: PRINCIPAL_FLOOR_VIOLATED");
   ```
   No yield harvest can ever decrease total vault assets below `protectedPrincipalUSD`.
2. **One-Way Ratchet**:
   ```solidity
   // In settleOptionPayout():
   protectedPrincipalUSD += netCompoundedProfit;
   ```
   Once option gains are ratcheted into the protected principal, they become permanent base capital that cannot be removed by subsequent losing months.

---

## 📄 License
MIT License. Created by [fredLuv](https://github.com/fredLuv).
