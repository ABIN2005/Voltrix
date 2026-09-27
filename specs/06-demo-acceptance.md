# Demo and acceptance specification

## Status

- Version: 0.6
- State: approved demo baseline
- Implementation authorized: implemented local pricing and settlement path;
  Prompt 0010 deployment architecture only until later checkpoints are reviewed

## Demo objective

In four minutes, demonstrate that AquaVol creates a real covered-call token,
prices it through a custom SwapVM program using live Aqua inventory, settles a
real CALL/USDC trade on Base Sepolia, and preserves physical exercise rights
against locked WETH.

## Canonical evidence topology

The primary demo MUST NOT depend on a developer laptop for already published
evidence. It SHOULD provide:

- a public React/Vite application;
- verified Base Sepolia contracts;
- public transaction and event links;
- deterministic seeded maker and trader state;
- a scripted local-fork fallback using the same contract interfaces.

The live Base Sepolia trade supplies the required public token-transfer
evidence. Time-dependent exercise uses a clearly labeled deterministic
local-fork replay. The demo MUST NOT pretend that Base Sepolia time was
manipulated.

## Prepared state

Before presenting, prepare:

- one funded testnet-only operator wallet acting as deployer, updater, writer,
  and maker under the disclosed hackathon profile;
- one funded trader test wallet;
- one active canonical CALL series;
- one exercise-ready series or deterministic fork snapshot;
- approved and shipped CALL/USDC Aqua balances;
- spot and volatility inputs producing a nontrivial premium;
- explorer links and a fallback transaction recording;
- testnet gas buffers.

Exact addresses and amounts belong in a deployment manifest, not hard-coded in
this specification.

## Four-minute sequence

### 0:00–0:25 — Problem and position

State:

> Options need collateral, liquidity, and risk-aware pricing. AquaVol separates
> those concerns: OptionSeries secures the claim, Aqua supplies self-custodied
> liquidity, and SwapVM makes the price programmable.

Show the active series and maker collateral.

### 0:25–0:55 — Real option creation

Show evidence that:

- the maker locked WETH;
- CALL tokens were minted one-to-one;
- WETH remains in OptionSeries rather than Aqua.

### 0:55–1:25 — Aqua strategy

Show:

- CALL and USDC virtual balances;
- strategy hash;
- immutable strike, expiry, gamma, spread, and oracle addresses;
- the Aqua shipping transaction or event.

### 1:25–2:00 — SwapVM quote

Show a quote breakdown containing:

- spot;
- strike;
- time remaining;
- implied volatility;
- Black-Scholes fair value;
- inventory before and after;
- average exposure;
- inventory adjustment;
- spread;
- final ask and taker maximum input.

The displayed numbers MUST reconcile with the authoritative router quote.

### 2:00–2:35 — Base Sepolia trade

The trader buys a fixed CALL quantity. Show wallet confirmation, transaction
hash, and successful confirmation.

Display before/after evidence:

```text
trader: USDC down, CALL up
maker:  USDC up, CALL down
Aqua:   virtual USDC up, virtual CALL down
```

### 2:35–3:05 — Inventory-driven repricing

Quote the same quantity again without changing the configured program. The ask
MUST be higher because the maker's remaining CALL inventory is lower.

State explicitly:

> The strategy program did not change. Aqua inventory changed, and that state
> changed the SwapVM result.

### 3:05–3:35 — Exercise

Using a prepared exercise-ready public series or labeled fork replay, show:

- holder pays strike USDC;
- CALL is burned;
- holder receives WETH;
- no spot oracle is consulted for exercise.

### 3:35–4:00 — Failure path and close

Show one fast failure path, preferably an expired taker deadline, excessive
maximum-input violation, or stale oracle rejection.

Close with:

> OptionSeries makes the claim solvent, Aqua makes liquidity reusable and
> self-custodied, and SwapVM makes fair value plus inventory risk executable.

## UI acceptance

The application MUST provide:

- clear wallet/network state;
- active series terms and lifecycle phase;
- maker collateral distinct from Aqua liquidity;
- quote inputs and output breakdown;
- loading, rejection, confirmation, and failure states;
- transaction and contract explorer links;
- token amounts with correct symbols and decimals;
- a visible disclosure for administrator-controlled volatility and any
  project-seeded Uniswap demo market.

A SwapVM trace panel is strongly preferred but MUST use real decoded values
rather than a hard-coded animation.

## Contract and test acceptance

From a clean checkout, documented commands MUST pass:

- formatting and compilation;
- option lifecycle unit tests;
- pricing-vector tests;
- fuzz tests for decimals and bounds;
- invariant tests for collateral and balances;
- Aqua/SwapVM integration tests;
- Base Sepolia read-only deployment verification;
- a deterministic demo replay.

## Submission evidence

The public repository SHOULD eventually include:

- architecture and lifecycle diagrams;
- pinned dependency provenance;
- generated, versioned test vectors;
- deployment manifest and explorer links;
- contract verification status;
- exact setup, test, and demo commands;
- implementation-status inventory;
- AI-use and prompt records;
- a two-to-four-minute narrated video without synthetic voiceover.

## Rehearsal gates

The demo is ready only when:

- the primary path succeeds twice from fresh browser sessions;
- the fallback path succeeds from a documented snapshot;
- every displayed amount reconciles with events and balances;
- no transaction requires editing source code or environment files live;
- confirmation delays have a recorded fallback;
- the presenter can explain the trusted inputs and non-production status;
- the complete sequence stays below four minutes.

## Approved demo decisions

- Canonical amounts and market parameters are defined in the product spec.
- Public token-transfer evidence comes from Base Sepolia.
- Exercise is demonstrated through a labeled deterministic local-fork replay.
- No backend is required for the canonical path.

Hosting, final wallet/explorer presentation, and the exact live failure path
remain operational decisions rather than blockers for the mathematical phase.
