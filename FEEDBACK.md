# Uniswap developer feedback

## Project

AquaVol uses an official Uniswap V3 deployment on Base Sepolia as the spot
source for a guarded WETH/avUSD time-weighted average price. The pool is seeded
with bounded hackathon-only liquidity through the official position manager.
The resulting TWAP is an input to Black-Scholes and inventory-aware pricing in
a modified 1inch SwapVM application.

The quote token, `AquaVol Demo USD` (`avUSD`), is project-issued test
infrastructure. It is not Circle USDC, and the pool is not represented as
production liquidity.

## Uniswap components used

- Uniswap V3 factory on Base Sepolia
- Nonfungible Position Manager for pool creation, initialization, and liquidity
- SwapRouter02 for the small swaps that write fresh observations
- V3 pool `observe`, `observations`, `slot0`, and `liquidity` reads
- TickMath and OracleLibrary algorithms adapted from pinned upstream revisions

The exact public addresses, pool configuration, provenance, and transaction
evidence are recorded in
[`docs/BASE_SEPOLIA_DEPLOYMENT.md`](docs/BASE_SEPOLIA_DEPLOYMENT.md) and
[`docs/UNISWAP_PROVENANCE.md`](docs/UNISWAP_PROVENANCE.md).

## What worked well

The V3 observation interface provides a compact and composable onchain source
for a manipulation-resistant demo price. Factory identity checks make it
possible for the adapter to verify that it is reading the expected pool rather
than trusting a supplied address. The same pool can support initialization,
liquidity, observation writes, and read-only TWAP calculation without a custom
offchain price service.

The official Base deployment registry was useful for pinning the factory,
position manager, SwapRouter02, and WETH addresses. Separating core pool reads
from periphery writes also made the integration straightforward to test with
narrow interfaces and a pinned Base Sepolia fork.

## Friction encountered

Testnet TWAP development requires real elapsed time unless the workflow uses a
local fork. A newly initialized pool cannot immediately answer a historical
`observe` request, and increasing observation capacity does not backfill
history. Clearer documentation connecting initialization, observation-cardinality
growth, observation writes, and the `OLD` revert would help developers avoid
mistaking capacity for accumulated history.

The address information needed for Base Sepolia is spread across protocol and
SDK-oriented resources. A single machine-readable official deployment manifest
covering every supported network, with provenance and last-updated metadata,
would reduce manual verification and hard-coded address risk.

Small custom test-token pools can also produce misleading confidence if a demo
does not disclose who seeded the liquidity. Examples that explicitly separate
canonical assets, project-issued test assets, and production-grade oracle
assumptions would improve hackathon integrations.

## Suggested improvements

1. Add an official TWAP lifecycle guide showing pool initialization, sufficient
   observation-cardinality configuration, elapsed-window requirements, a swap
   that writes a new observation, and common `observe` failures.
2. Publish a versioned JSON deployment registry for all supported chains and
   testnets alongside the human-readable deployment pages.
3. Provide a small reference checker that validates factory/pool identity,
   token ordering, fee tier, observation history, harmonic liquidity, and
   latest-observation age.
4. Include guidance for safely labeling and demonstrating project-seeded
   testnet pools.

## Relevant implementation

- [`contracts/src/oracles/uniswap/UniswapV3TwapOracle.sol`](contracts/src/oracles/uniswap/UniswapV3TwapOracle.sol) — guarded TWAP adapter
- [`contracts/src/oracles/uniswap/UniswapV3OracleMath.sol`](contracts/src/oracles/uniswap/UniswapV3OracleMath.sol) — cumulative tick and quote math
- [`contracts/src/oracles/uniswap/UniswapV3TickMath.sol`](contracts/src/oracles/uniswap/UniswapV3TickMath.sol) — pinned tick conversion
- [`contracts/script/BootstrapUniswapV3Pool.s.sol`](contracts/script/BootstrapUniswapV3Pool.s.sol) — official periphery pool bootstrap
- [`contracts/script/WriteTwapObservation.s.sol`](contracts/script/WriteTwapObservation.s.sol) — maturity check and observation write
- [`contracts/test/oracles/UniswapV3TwapOracle.t.sol`](contracts/test/oracles/UniswapV3TwapOracle.t.sol) — identity, freshness, liquidity, deviation, and rounding tests
- [`contracts/test/fork/BaseSepoliaDeploymentRehearsal.t.sol`](contracts/test/fork/BaseSepoliaDeploymentRehearsal.t.sol) — complete pinned-fork integration rehearsal

## Submission status

The repository feedback file is complete. Submission of the required Uniswap
Developer Feedback Form remains a manual project-owner action. The form should
link directly to this public file after the relevant commit is pushed.
