# Uniswap V3 TWAP oracle specification

## Status

- Version: 0.2
- State: implemented and tested, including read-only Base Sepolia evidence
- Updated: 2026-09-26
- Implementation authorization: Prompt 0007 checkpoints complete; Prompt 0010
  may deploy the adapter after its preflight and rehearsal gates

## Objective

Provide AquaVol with a deterministic, strategy-bound USDC-per-WETH spot input
derived from an official Uniswap V3 pool. The adapter must expose enough
evidence for SwapVM, tests, and the UI to explain the averaging window and reject
an uninitialized, inactive, incorrect, or insufficiently liquid pool.

This phase does not implement Black-Scholes, implied volatility, inventory
skew, strategy encoding, or deployment transactions.

## Oracle interface

The adapter SHOULD expose one read returning at least:

```text
priceWad                  USDC per one WETH, 18 decimals
arithmeticMeanTick        signed mean tick over the complete window
harmonicMeanLiquidity     V3 harmonic-mean in-range liquidity
windowStart               block timestamp minus the immutable window
windowEnd                 current block timestamp
latestObservationTime     timestamp of the latest initialized pool observation
```

The adapter is view-only. It has no owner, updater, fallback price, or mutable
configuration.

## Immutable configuration

Construction MUST bind:

- official Uniswap V3 factory;
- expected pool;
- base token and its required 18 decimals;
- quote token and its required 6 decimals;
- fee tier;
- nonzero TWAP window;
- minimum harmonic-mean liquidity;
- maximum age of the latest initialized observation;
- maximum allowed deviation between current tick and TWAP tick, or an explicit
  value disabling this optional circuit breaker.

The constructor MUST confirm that `factory.getPool(base, quote, fee)` returns
the configured pool and that each address has contract code.

## TWAP calculation

The adapter MUST use the V3 pool observation accumulators over exactly:

```text
[twapWindow, 0]
```

Mean tick division MUST round toward negative infinity as the official
`OracleLibrary.consult()` algorithm does. The spot quote MUST be derived from
the mean tick, not from the current `slot0` price. Current tick MAY be read only
for a fail-closed deviation check.

The result MUST normalize a quote for one `1e18` base-token unit into an
18-decimal price WAD, independent of whether WETH is token0 or token1. Any
overflow, zero result, or price above `1_000_000e18` MUST revert.

## Observation and liquidity guards

A read MUST revert when:

- the pool cannot serve the complete window;
- the latest indexed observation is uninitialized or zero-dated;
- the latest observation age exceeds `maxObservationAge`;
- current liquidity is zero;
- harmonic-mean liquidity is below the configured minimum;
- the optional current-versus-TWAP deviation limit is exceeded;
- the pool pair, fee, or factory identity no longer matches configuration.

Observation cardinality alone is not proof of useful history. Tests MUST cover
a pool with a nonzero cardinality that still lacks the requested time window.

## Base Sepolia profile

The target chain is Base Sepolia (`84532`). Addresses verified with read-only
RPC calls on 2026-09-26:

| Component | Address |
| --- | --- |
| Uniswap V3 factory | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` |
| V3 position manager | `0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2` |
| V3 swap router | `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4` |
| Canonical WETH | `0x4200000000000000000000000000000000000006` |
| Circle test USDC candidate | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

All addresses MUST be rechecked in the official registries and onchain by the
deployment script. No address becomes a contract constant solely because it is
listed in this document.

## Public demo market

The deterministic Base Sepolia demo SHOULD use canonical WETH and a clearly
named, controlled DemoUSDC deployed by AquaVol. Its WETH/DemoUSDC pool MUST be
created through the official V3 factory, initialized near the canonical 3,800
USDC-per-WETH scenario, supplied with bounded test liquidity, and allowed to
accumulate the complete TWAP window before the demo.

The deployment manifest MUST record pool creation, initialization, liquidity,
observation-cardinality, and heartbeat transactions. The UI MUST label this as
a project-seeded test market. Existing canonical WETH/test-USDC pools MAY be
shown as comparison data but MUST NOT silently replace the configured strategy
oracle.

## Source and license boundary

The official V3 OracleLibrary targets a pre-0.8 Solidity range, while AquaVol
uses Solidity 0.8.30. Prompt 0007 MAY implement a narrowly scoped 0.8 adaptation
of the official consult and tick-quote algorithms. Every adapted file MUST:

- use the applicable `GPL-2.0-or-later` SPDX identifier;
- cite the exact pinned upstream file and revision;
- mark AquaVol modifications and their date;
- preserve notices and make corresponding source available;
- remain isolated under `contracts/src/oracles/uniswap` with directly related
  tests clearly identified.

No upstream source may be silently copied or relicensed.

## Checkpoint 2 acceptance

Local tests using a controllable V3-pool double MUST prove:

- positive and negative mean-tick rounding;
- token-order inversion and 18/6 decimal normalization;
- canonical tick-to-price vectors against an independent reference;
- full-window, latest-observation, liquidity, and deviation guards;
- factory/pool/pair/fee validation;
- no storage mutation or external token movement.

## Checkpoint 3 acceptance

Read-only Base Sepolia verification MUST:

- confirm chain ID and bytecode at official deployment addresses;
- resolve pools through the factory rather than trust a copied address;
- read at least one complete 30-minute canonical-pool observation;
- record pool tick, liquidity, cardinality, and observation behavior without
  claiming that testnet price quality is production-grade;
- leave all upstream references and submodules clean;
- keep RPC-dependent checks separate from the default offline suite.

The implementation is not accepted as production-oracle safety. Testnet market
manipulation, sequencer behavior, and liquidity concentration remain disclosed
risks.
