# AquaVol MVP product specification

## Status

- Version: 0.6
- State: approved MVP baseline
- Implementation authorized: reference math, OptionSeries, protocol routing,
  spot oracle, fair value, and inventory-aware pricing; deployment architecture
  is ready for review under Prompt 0010 checkpoint 1
- Network target: Base Sepolia

The words **MUST**, **MUST NOT**, **SHOULD**, and **MAY** describe normative
requirements for the MVP.

## Product statement

AquaVol is a programmable market for fully collateralized European covered
calls. A maker locks WETH to mint CALL tokens, exposes CALL and USDC liquidity
through Aqua, and publishes an immutable SwapVM program that calculates an
executable price from option fair value and current inventory risk.

## User-visible claim

> Create a covered call, trade it from self-custodied Aqua liquidity, watch its
> executable price react to time, market inputs, and maker inventory, and
> exercise it for the underlying asset after expiry.

## Actors and incentives

### Maker and writer

The MVP uses one address as both writer and market maker. The maker:

- locks WETH and receives CALL inventory;
- supplies virtual CALL and USDC balances to an Aqua strategy;
- receives premiums when selling CALL tokens;
- spends USDC when buying previously sold CALL tokens back;
- accepts covered-call exposure for the exercise window;
- recovers remaining WETH and exercise proceeds after settlement.

### Trader

The trader:

- buys CALL tokens by paying USDC;
- MAY sell purchased CALL tokens back while the market is active and the maker
  has sufficient virtual USDC;
- MAY exercise CALL tokens during the exercise window by paying the strike in
  USDC and receiving WETH.

### Administrator

For the MVP, an administrator updates only the volatility registry. Spot comes
from the strategy-bound Uniswap V3 TWAP oracle. In the local security model,
this role SHOULD remain separate from the writer and maker. The Base Sepolia
hackathon deployment MAY consolidate deployer, volatility updater, writer, and
maker into one disclosed, testnet-only operator wallet. It MUST still use a
distinct trader wallet and cannot bypass contract collateral rules or control
trader-held tokens. The UI and documentation MUST identify volatility as a
trusted demo input, disclose the consolidated role, and identify the selected
Uniswap pool as a project-seeded test market.

## Canonical market

The canonical demo MUST use:

| Field | Value |
| --- | --- |
| Underlying | WETH, 18 decimals |
| Quote asset | USDC, 6 decimals |
| Option style | European covered call |
| Option decimals | 18 |
| Collateral ratio | 1 WETH per 1 whole CALL |
| Writer count | One per series |
| Strike count | One in the canonical path |
| Expiry count | One active expiry in the canonical path |
| Buy mode | Exact-output CALL |
| Sell-back mode | Exact-input CALL |
| Exercise settlement | Physical WETH delivery for strike USDC |

The canonical parameters are:

| Parameter | Approved value |
| --- | --- |
| Written collateral | 10 WETH |
| Initial CALL inventory | 10 CALL |
| Virtual quote liquidity | 5,000 USDC |
| Strike | 4,000 USDC per WETH |
| Initial demo spot | 3,800 USDC per WETH |
| Initial time to expiry | Seven days |
| Implied volatility | 64% annualized |
| Inventory gamma | 20% |
| Half-spread | 1% |
| Exercise window | 24 hours |

## Component responsibilities

### OptionSeries

`OptionSeries` MUST:

- define immutable underlying, quote, strike, expiry, exercise window, and
  writer;
- accept WETH collateral from the writer;
- mint CALL tokens one-to-one with WETH collateral;
- burn exercised CALL tokens;
- collect strike USDC and deliver WETH during valid exercise;
- allow the writer to redeem settlement proceeds after the window closes.

It MUST NOT calculate market prices or depend on an oracle for exercise.

### Aqua

Aqua MUST:

- identify the strategy from its canonical encoded order;
- track virtual CALL and USDC balances;
- execute maker-side token transfers during accepted trades;
- expose current balances to the Aqua-aware SwapVM execution path.

Aqua virtual balances MUST NOT be described as option collateral.

### SwapVM

The modified SwapVM deployment MUST:

- execute the same strategy program for quotes and swaps;
- obtain fair value from approved spot, volatility, strike, and time inputs;
- modify the executable price using the strategy's current CALL inventory;
- enforce direction, deadline, amount threshold, and balance constraints;
- leave custody and final token movement to the established settlement path.

### Browser application

The React/Vite application MUST show:

- series terms and lifecycle state;
- fair value, inventory adjustment, spread, bid, and ask;
- current Aqua virtual CALL and USDC balances;
- wallet approvals and transaction progress;
- transaction hashes and post-trade balances;
- the distinction between trusted demo inputs and trustless collateral rules.

### Python reference model

Python MUST provide independent Black-Scholes reference results and deterministic
test vectors. It MUST NOT be called by contracts or required for the live demo.

## MVP capabilities

The MVP is complete only if it supports:

1. writing a fully collateralized series;
2. shipping one canonical Aqua-backed strategy;
3. quoting and buying an exact CALL quantity;
4. visibly repricing after CALL inventory decreases;
5. selling no more CALL inventory back than the strategy previously sold;
6. exercising during the exercise window;
7. writer redemption after the exercise window;
8. rejection of an expired trade or unacceptable execution threshold;
9. deterministic Python/Solidity pricing comparison;
10. public Base Sepolia token-transfer evidence.

## Non-goals

The MVP does not include:

- puts, American exercise, cash settlement, or early exercise;
- multiple writers in one series;
- margin, leverage, liquidation, or naked options;
- fungible short-position tokens;
- decentralized volatility discovery;
- production oracle guarantees;
- a volatility surface or portfolio Greeks;
- cross-chain settlement;
- a general-purpose options exchange;
- a backend required for successful settlement.

## Stretch goals

After the canonical path is complete, the project MAY add:

- three strikes sharing the maker's wallet USDC through separate Aqua
  strategies;
- a bid/ask option table;
- a SwapVM trace panel;
- volatility interpolation;
- portfolio risk views.

## Product acceptance

The one-writer restriction, canonical parameters, administrator-controlled
volatility, and buyback support are approved for the MVP. Prompt 0004
authorized `OptionSeries`; Prompt 0005 authorized the pinned unmodified
Aqua/SwapVM baseline; Prompt 0006 completed the custom-router foundation;
Prompt 0007 completed the Uniswap spot-oracle checkpoints, Prompt 0008 completed
the bounded volatility and fair-value path, and Prompt 0009 completed
inventory-aware Aqua repricing. Prompt 0010 defines the review-gated Base
Sepolia deployment. Deployment tooling, public deployment, and browser
implementation remain incomplete.
