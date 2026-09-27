# Frontend strategy workspace specification

## Status

- Version: 0.1
- State: initial implementation authorized
- Updated: 2026-09-26

## Objective

Present AquaVol as a strategy-oriented options interface that makes its live
Base Sepolia market, simulated option strategies, payoff behavior, and protocol
composition understandable in one demo-ready experience.

## Product boundary

The deployed WETH 4,000 CALL expiring 2026-10-04 is the only instrument that
may be labelled live. Other strikes, expiries, and every PUT are simulations.
The interface must never imply that a simulated instrument is executable.

The initial frontend is read-only and uses the recorded public deployment
snapshot. Wallet connection, fresh RPC reads, quote construction, approvals,
and settlement are a later checkpoint.

## Required workspace

- a dark, responsive protocol identity distinct from the reference project;
- live WETH TWAP, volatility, strike, expiry, and next-ask summary;
- editable multi-leg CALL and PUT strategies with a maximum of four legs;
- reusable presets for the live call, a bull call spread, and a straddle;
- a strike ladder with explicit `LIVE` and `SIM` status on every row;
- an interactive expiration payoff chart with profit, loss, TWAP, and tooltip;
- net premium, breakeven, and sampled payoff bounds;
- an onchain proof section linking the public trade and deployed contracts;
- an architecture path from Uniswap through pricing and SwapVM to Aqua.

## Calculation rules

Simulated premiums use zero-rate, zero-dividend Black-Scholes with the public
64% volatility snapshot. Live displayed execution values use the recorded
onchain quote and settlement evidence because inventory skew and spread make
them intentionally different from isolated fair value. Payoff calculations
must treat quantity as underlying-token units and must reverse sign for sold
legs.

## Acceptance

- the application builds with TypeScript and Vite;
- mobile and desktop layouts retain all material labels;
- payoff remains defined for an empty or multi-leg strategy;
- a zero payoff remains visible and hoverable;
- external evidence opens on BaseScan;
- no private key, RPC credential, or populated environment file is required;
- no transaction button suggests execution before wallet integration exists.
