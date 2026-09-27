# Security and invariant specification

## Status

- Version: 0.2
- State: draft for security review
- Production readiness claimed: no

## Security posture

AquaVol is hackathon software. The MVP MUST make no claim of audit, formal
verification, production oracle safety, or mainnet readiness. Security tests
provide evidence for the stated bounded design only.

## Trust boundaries

### Trust-minimized properties

- CALL supply is backed one-to-one by WETH held in `OptionSeries`.
- Series terms are immutable.
- Exercise requires strike USDC and burns the exercised CALL.
- Aqua/SwapVM execution enforces the encoded program and token balances.

### Trusted MVP components

- economic quality and manipulation resistance of the selected Uniswap V3
  market, especially when project-seeded on a testnet;
- administrator updates to the volatility registry;
- correctness of pinned upstream Aqua, SwapVM, SDK, math, and token libraries;
- Base Sepolia infrastructure and RPC availability.

The UI and documentation MUST expose these boundaries.

## OptionSeries invariants

Before final redemption:

```text
totalWritten == total CALL ever minted for writing
totalExercised <= totalWritten
WETH delivered == totalExercised
live WETH collateral == totalWritten - totalExercised
```

Additional requirements:

- only the immutable writer can write or redeem;
- writing is allowed only before expiry;
- exercise is allowed only inside the exercise window;
- each exercised CALL is burned exactly once;
- exercise USDC is not confused with Aqua trading premiums;
- writer redemption occurs at most once and only after the window;
- no administrative function can withdraw collateral early.

## Trading invariants

For unchanged state, quote and swap MUST return identical token amounts.

For buys:

- requested CALL output is nonzero;
- CALL output does not exceed current Aqua CALL balance;
- required USDC rounds upward;
- larger purchases do not receive a better average price;
- CALL inventory and short exposure move in opposite directions.

For sell-backs:

- CALL input is nonzero;
- USDC output does not exceed current Aqua USDC balance;
- USDC output rounds downward;
- resulting CALL inventory does not exceed `Q0`;
- short exposure cannot become negative.

For both directions:

- input and output tokens match the bound strategy pair;
- unsupported exact-in/exact-out combinations revert;
- taker deadline and amount threshold are enforced;
- self-transfer and zero-recipient behavior follows explicit upstream rules;
- token and Aqua virtual-balance deltas reconcile with emitted events.

## Pricing invariants

- `N(x)` lies in `[0, 1]` and is monotonic.
- Fair call value lies in `[max(S-K,0), S]`.
- Ask is not below bid for identical state.
- Increased short exposure MUST NOT reduce the ask.
- Increased short exposure SHOULD increase the bid under the approved buyback
  model, while bid remains below ask.
- Multi-unit integrated pricing is additive within declared rounding error.
- An invalid or out-of-domain mathematical result reverts rather than wrapping,
  truncating into a plausible value, or producing an unchecked quote.

## Oracle validation

Each oracle read MUST validate:

- expected interface and successful return-data decoding;
- positive value;
- configured minimum and maximum;
- nonzero update time;
- update time not materially in the future;
- independent freshness limit;
- correct quote denomination.

Oracle addresses MUST be bound into the immutable strategy. Administrator
updates MUST emit events. Production-oriented deployments SHOULD keep the
volatility updater separate from collateral and maker liquidity. The Base
Sepolia hackathon profile MAY consolidate updater, writer, and maker in one
disclosed testnet-only operator, but MUST keep the trader identity separate and
MUST NOT weaken collateral, authorization, freshness, or settlement checks.

For a Uniswap V3 TWAP read, validation MUST additionally cover:

- the pool returned by the configured official factory for the exact token pair
  and fee tier;
- token order and decimal normalization;
- nonzero current and harmonic-mean liquidity;
- sufficient initialized history for the complete configured window;
- a recently written latest observation rather than silently extrapolating an
  inactive testnet pool indefinitely;
- an optional current-price versus TWAP deviation circuit breaker that only
  halts pricing and never substitutes the current price.

## Arithmetic and decimals

- WAD and token-native values MUST use distinct types or clearly named
  variables.
- All WAD-to-USDC conversions MUST specify rounding direction.
- Full-precision multiplication/division is required where intermediates could
  overflow.
- Signed-to-unsigned conversions require explicit nonnegative checks.
- Exponential, logarithm, square-root, and CDF domains require pre-validation.
- Fuzz tests MUST include maximum approved values and fractional CALL amounts.

## Token assumptions

WETH, USDC, and CALL tokens in the MVP MUST be standard ERC-20 assets with:

- no transfer fee;
- no rebasing;
- no transfer callback;
- stable decimals;
- conventional success or revert behavior.

Any mock token MUST reproduce the decimals and transfer semantics used by the
application.

## Reentrancy and call ordering

- OptionSeries state MUST be updated consistently around external transfers and
  protected against reentrancy.
- Pricing instructions MUST NOT transfer tokens or invoke arbitrary unbound
  targets.
- The modified router MUST retain upstream reentrancy and callback protections.
- Callback origin, maker, application, strategy hash, and expected post-push
  balance MUST be validated where applicable.

## Authorization and replay protection

- Aqua mode MUST bind execution to the maker and shipped strategy.
- Orders MUST include unique identity where the upstream format requires it.
- Taker data MUST include a short deadline.
- Reusing stale or altered strategy bytes MUST not resolve to the funded
  strategy.
- Oracle administration MUST use an explicit owner role and emit changes.

## Failure-path requirements

Tests MUST cover:

- undercollateralized write attempt;
- exercise outside the window;
- repeated exercise and redemption;
- zero, stale, future-dated, or out-of-range oracle data;
- zero or excessive volatility;
- insufficient CALL and insufficient USDC liquidity;
- sell-back above initial inventory;
- expired deadline and violated slippage threshold;
- unsupported direction and execution mode;
- arithmetic boundary and CDF tail values;
- malicious or nonstandard token rejection where feasible;
- reentrant exercise attempt.

## Operational safeguards

- Never use a production wallet or mainnet private key.
- Keep secrets outside Git and browser bundles.
- Verify deployed bytecode and constructor arguments.
- Record deployment chain ID, addresses, transaction hashes, source commits, and
  explorer links.
- Maintain a local-fork fallback demo without presenting it as the public
  deployment.

## Exit criteria

Security review is complete for the hackathon MVP only when:

- every invariant maps to at least one unit, fuzz, invariant, or integration
  test;
- all accepted trust assumptions appear in the UI or public documentation;
- unresolved high-severity findings are visible and block production claims;
- the complete demo can fail safely under stale price, exhausted liquidity,
  and adverse slippage conditions.
