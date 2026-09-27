# AquaVol foundation specification

## Document status

- Stage: phased implementation
- Version: 0.2
- Updated: 2026-09-26
- Implementation authorized: only through reviewed phase prompts

This document records the project-wide foundation. Detailed implementation
authority comes only from the latest reviewed product specifications and phase
prompts; this document must not be treated as approval to invent missing
economic behavior.

## Project intent

AquaVol will demonstrate a sophisticated DeFi position whose liquidity and
settlement use Aqua, with SwapVM included when it materially improves the
position rather than serving as a cosmetic integration.

The final demonstration must make the position understandable through visible
state changes and real token movements onchain.

## Fixed constraints

- Frontend: React, TypeScript, and Vite.
- Backend: Node.js and TypeScript.
- Contracts: Solidity developed and tested with Foundry.
- Demonstration network: Base Sepolia.
- Mathematical reference environment: Python.
- Black-Scholes is currently a candidate model, not yet an approved settlement
  formula.
- Official Aqua or SwapVM contract sources must remain identifiable.
- The repository must preserve specifications, prompts, decisions, tests, and
  material AI assistance.
- Secrets, funded private keys, and populated environment files must never be
  committed.

## System boundaries

### Browser application

The browser application will present position inputs, wallet actions, quotes,
transaction state, and post-transaction evidence. It must not be the sole
authority for amounts enforced during settlement.

### TypeScript service

The service may normalize market inputs, coordinate quotes, encode strategies,
and expose indexed state. Whether it is required for the canonical demo remains
an open decision. The demo should avoid a fragile dependency unless the service
provides essential behavior.

### Solidity contracts

Contracts are the settlement authority. They must enforce token identity,
amount limits, deadlines, replay protection, authorization, and any economic
bounds required by the chosen position.

### Python reference model

Python will be used for model exploration, high-precision calculations, and
deterministic test-vector generation. It will not be a trusted component in a
live transaction. Any equivalent TypeScript or Solidity calculation must be
tested against the same vectors with declared error and rounding limits.

## Decisions tracked during implementation

1. What assets does a maker allocate, and what exposure do they receive?
2. Who takes the other side of the position and why would they participate?
3. Is the position a call, put, volatility band, dynamic liquidity policy, or
   another structure?
4. Which values are immutable when a strategy is shipped?
5. Which values change after a fill, expiry, rebalance, or cancellation?
6. Where do spot price, volatility, interest rate, and time-to-expiry originate?
7. Which calculations must execute onchain?
8. Does SwapVM need a new instruction, or can existing instructions compose the
   required behavior?
9. What exact token transfers will judges see in the canonical demo?
10. What adverse path will the demo or tests show being rejected?

## Entry gate for implementation

Implementation may start after a product specification defines:

- the actors and their incentives;
- the complete position lifecycle;
- token and decimal conventions;
- mathematical formulas and bounded domains;
- trust assumptions and failure behavior;
- Aqua and SwapVM responsibilities;
- exact-input and exact-output behavior where applicable;
- security invariants;
- one deterministic end-to-end demo scenario.

The specification must include at least one worked numerical example that can
become a cross-language test vector.

## Minimum demo evidence

The eventual canonical demo should show:

1. a wallet creates or funds a position;
2. the resulting Aqua strategy identity and balances are visible;
3. another actor receives a quote and submits a transaction;
4. the transaction transfers tokens on Base Sepolia;
5. the UI displays the transaction hash and resulting position state;
6. a constraint violation is rejected either live or by a clearly linked test.

## Explicitly deferred

- Production security claims.
- Mainnet deployment.
- Governance and protocol fees.
- Cross-chain operation.
- Leverage and liquidation systems.
- A general-purpose derivatives protocol.
- UI polish before the end-to-end settlement path works.
