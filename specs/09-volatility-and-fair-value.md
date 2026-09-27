# Volatility registry and fair-value specification

## Status

- Version: 0.2
- State: implemented and tested
- Updated: 2026-09-26
- Implementation authorization: Prompt 0008 checkpoints complete; Prompt 0010
  may deploy the registry and fair-value path after its review gates

## Objective

Replace the temporary fixed premium with a bounded, explainable European-call
fair value. The pricing path combines the existing strategy-bound Uniswap V3
TWAP spot with a separately administered implied-volatility value and immutable
`OptionSeries` terms.

This phase does not implement inventory skew, spread, TypeScript encoding,
frontend work, deployment transactions, or public strategy shipping.

## Trust boundary

Spot and volatility have deliberately different trust models:

- spot is derived from the immutable Uniswap V3 TWAP adapter;
- implied volatility is written by one disclosed administrator because it
  cannot be inferred from a spot feed alone;
- strike and expiry come from the immutable CALL token contract;
- every accepted quote checks each source independently and fails closed.

By default, the volatility administrator holds no collateral and cannot
exercise, redeem, ship, dock, or transfer maker inventory. The Base Sepolia
hackathon profile in `specs/11-base-sepolia-deployment.md` explicitly permits a
testnet-only operator to combine administrator, writer, and maker roles while
keeping the trader separate. In either profile, the updater can influence
trading prices, so the UI and demo MUST identify this role and any consolidation.

## Volatility registry

`VolatilityRegistry` MUST bind one nonzero immutable updater at construction.
It stores one record per `OptionSeries` address:

```text
volatilityWad   annualized implied volatility, 18 decimals
updatedAt       block timestamp of the accepted update
```

The supported value range is:

```text
0.0001e18 <= volatilityWad <= 5e18
```

This represents 0.01% through 500% annualized volatility. An update MUST:

- come from the immutable updater;
- reference an address with deployed code;
- remain inside the supported range;
- replace the timestamp with the current block timestamp;
- emit the series, previous value, new value, and update time.

Unconfigured records return zero value and zero time so consumers reject them.
There is no fallback value, backdated update, arbitrary timestamp setter,
ownership transfer, token recovery, or generic external call. Loss of the
updater key causes records to become stale and trading to stop safely.

## Fixed-point dependency

The approved candidate is PRBMath `v4.2.0`, resolved to commit:

```text
29a3c06c709496a8f9775dea115935befc5158a7
```

PRBMath is MIT licensed, supports Solidity `>=0.8.19`, and provides the signed
59.18 and unsigned 60.18 logarithm, exponential, multiplication, division, and
square-root operations required by the model. AquaVol compiles with Solidity
0.8.30.

Checkpoint 3 MUST install the exact revision as a Git submodule under
`contracts/lib/prb-math`, record its license, and import only specific symbols.
No floating-point implementation or offchain result becomes authoritative for
settlement.

## Normal CDF

`NormalCDF` MUST use the Abramowitz and Stegun 26.2.17 polynomial form with the
following decimal coefficients encoded as signed WAD values:

```text
p  =  0.2316419
b1 =  0.319381530
b2 = -0.356563782
b3 =  1.781477937
b4 = -1.821255978
b5 =  1.330274429
```

The density term is:

```text
phi(x) = exp(-(x*x)/2) / sqrt(2*pi)
```

The implementation MUST:

- return a WAD value in `[0, 1e18]`;
- saturate to `0` at `x <= -8e18` and `1e18` at `x >= 8e18` before evaluating
  the exponential;
- calculate the positive half and derive the negative half by symmetry;
- be monotonically nondecreasing across the committed test grid;
- keep maximum measured absolute error at or below `2e-6` against Python's
  `math.erf` reference on `[-8, 8]`;
- document rounding and every coefficient in source.

## Black-Scholes call model

The Solidity library implements only the approved zero-rate, zero-dividend
European call:

```text
d1 = (ln(S / K) + 0.5 * sigma^2 * T) / (sigma * sqrt(T))
d2 = d1 - sigma * sqrt(T)
C  = S * N(d1) - K * N(d2)
```

Inputs and output use 18-decimal WAD units. Active pricing accepts:

| Input | Accepted domain |
| --- | --- |
| Spot | `(0, 1_000_000e18]` |
| Strike | `(0, 1_000_000e18]` |
| Time remaining | `(0, 366 days]` |
| Volatility | `[0.0001e18, 5e18]` |

Time in years is calculated from integer seconds using a 365-day year and
full-precision multiplication/division. The reusable math library MUST still
define `time == 0` or `volatility == 0` as intrinsic value, but the live opcode
rejects expired and zero-volatility inputs before calling it.

The result MUST satisfy:

```text
max(S - K, 0) <= C <= S
```

The measured CDF error gives a conservative call-value error budget of:

```text
(S + K) * 2e-6 + fixed-point rounding allowance
```

If the raw approximation misses the intrinsic or spot bound by no more than
that budget, the library MUST clamp to the corresponding analytical bound. The
specific clamp paths MUST be tested. Any larger deviation, invalid signed
conversion, unsupported PRBMath domain, or arithmetic failure MUST revert.
Runtime trading also rejects a zero premium because it cannot produce a safe
executable token amount.

## Fair-value instruction

Opcode `0xd1` remains `OPTION_FAIR_VALUE`. Its immutable program arguments are:

```text
CALL token / OptionSeries address
USDC quote-token address
UniswapV3TwapOracle address
VolatilityRegistry address
maximum volatility age
```

The five fields use standard ABI encoding and occupy 160 bytes, below SwapVM's
one-byte argument-length limit. Strike and expiry are not duplicated: the
instruction reads them from the bound `OptionSeries` contract. The registry is
keyed by that same CALL-token address.

All external pricing reads MUST be compiler-generated static calls to addresses
committed into the maker's strategy bytes. No target comes from taker data.
The instruction MUST validate:

- exactly one supported pair and direction;
- exact-output USDC-to-CALL for a buy, or exact-input CALL-to-USDC for a
  sell-back;
- nonzero requested CALL amount and sufficient relevant Aqua balance;
- current time strictly before series expiry;
- successful guarded TWAP read and spot within the approved domain;
- configured volatility inside its domain;
- nonzero volatility timestamp;
- timestamp no more than 15 seconds in the future;
- volatility age no greater than the bound strategy limit;
- nonzero maximum age no greater than seven days;
- positive fair value no greater than spot.

The instruction writes only the missing swap amount register:

- buy: required USDC input rounds upward;
- sell-back: delivered USDC output rounds downward.

Conversion from premium WAD and 18-decimal CALL quantity to 6-decimal USDC MUST
use full-precision arithmetic with the combined `1e30` scale. The instruction
does not transfer tokens or mutate storage.

## Inventory separation

`OPTION_FAIR_VALUE` computes unskewed fair value only. A later prompt will
implement `OPTION_INVENTORY_SKEW` at opcode `0xd2`, consuming current Aqua
balances and applying average exposure plus spread. This phase MUST NOT hide
inventory behavior inside the fair-value instruction.

## Test acceptance

Tests MUST cover:

- registry authorization, bounds, series-code check, timestamps, and events;
- CDF tails, symmetry, monotonicity, and the committed Python grid;
- all canonical Black-Scholes vectors within the larger of `0.10` USDC or 10
  basis points;
- intrinsic-value boundaries and every accepted input maximum;
- one unit outside every rejected domain boundary;
- fair-value invariants across fuzzed bounded inputs;
- fresh, stale, future-dated, missing, zero, and excessive volatility;
- stale or otherwise rejected spot-oracle reads;
- exact-output buy ceiling rounding and exact-input sell-back floor rounding;
- altered instruction bytes resolving to a different unfunded Aqua strategy;
- quote/swap equality and real/virtual balance reconciliation;
- no opcode storage mutation or direct token movement;
- unchanged pinned Aqua and SwapVM submodules and passing upstream suites.

## Security status

Passing this phase proves bounded numerical and integration behavior only. It
does not make Black-Scholes assumptions correct for real markets, remove
volatility-administrator trust, establish Uniswap manipulation resistance, or
make the contracts audited or production-ready.
