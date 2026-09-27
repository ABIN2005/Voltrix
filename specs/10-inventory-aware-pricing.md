# Inventory-aware pricing specification

## Status

- Version: 0.2
- State: implemented and tested; temporary constant-price scaffold retired
- Updated: 2026-09-26
- Implementation authorization: Prompt 0009 checkpoints complete; Prompt 0010
  may deploy the inventory-aware strategy after its review gates

## Objective

Add a storage-free SwapVM instruction that adjusts the existing Black-Scholes
fair-value quote using the CALL balance already loaded from the maker's Aqua
strategy. The same immutable program must produce a different executable quote
after settlement changes its virtual inventory.

This phase does not change the option model, spot or volatility trust models,
collateral lifecycle, protocol submodules, or public deployment profile.

## Separation of responsibilities

The canonical pricing program is:

```text
OPTION_FAIR_VALUE (0xd1)
    reads strategy-bound market and series data
    writes the unskewed total USDC amount
            |
            v
OPTION_INVENTORY_SKEW (0xd2)
    reads live Aqua balances already present in the SwapVM context
    applies average exposure, gamma, and spread
    writes the final total USDC amount
            |
            v
upstream threshold validation and Aqua settlement
```

`0xd1` remains the authority for fair value. `0xd2` MUST consume its amount
register rather than recompute Black-Scholes or accept a taker-provided price.
Neither instruction transfers tokens or mutates storage.

### Runtime execution boundary

On the deployable router, `0xd1` and `0xd2` are dispatched through an immutable
`AquaVolPricingEngine`. The router supplies only the strategy arguments,
token-direction query fields, Aqua balances already loaded into the SwapVM
context, and current amount registers. The engine performs the same validations
and mathematics specified below and returns the two amount registers.

This split is an EIP-170 code-size boundary, not a new pricing authority. The
engine is stateless and read-only; it cannot ship or dock an Aqua strategy,
settle tokens, change series terms, update volatility, or alter the immutable
program. Replacing the engine requires deploying a different router and
shipping a strategy bound to that router.

## Immutable instruction encoding

Opcode `0xd2` is `OPTION_INVENTORY_SKEW`. Its arguments are:

```text
CALL token / OptionSeries address
USDC quote-token address
UniswapV3TwapOracle address
initial CALL inventory Q0
inventory gamma WAD
half-spread WAD
```

The six fields use standard ABI encoding and occupy 192 bytes, below SwapVM's
one-byte argument-length limit. All addresses and economic parameters are part
of the maker's immutable strategy bytes. Taker data supplies none of them.
The complete instruction begins with the two-byte header `0xd2c0`, followed by
the 192 ABI-encoded argument bytes.

The oracle is repeated from `0xd1` deliberately. `0xd2` revalidates its base
and quote identity and reads the guarded spot solely to enforce the final
premium cap. Changing the oracle or any economic parameter changes the
strategy hash and requires a newly shipped strategy.

## Accepted domains

| Value | Accepted domain |
| --- | --- |
| `Q0` | `[1, type(uint128).max]` CALL native units |
| Current CALL inventory `Q` | `[0, Q0]` |
| Trade CALL quantity `q` | `(0, Q0]` and inside direction-specific inventory |
| Gamma | `[0, 1e18]` |
| Half-spread | `[0, 0.25e18]` |
| Average exposure | `[0, 1e18]` |
| Input fair-value quote | positive USDC native units |
| Final quote | positive, liquid, and no greater than the guarded spot cap |

Zero gamma and zero spread are valid explicit configurations. They are useful
for isolation tests and still leave all inventory bounds active.

## Live balance selection

The SwapVM context has already loaded the maker's Aqua balances for the bound
pair.

For an exact-output USDC-to-CALL buy:

```text
Q = balanceOut
q = amountOut
require q <= Q
Qafter = Q - q
```

For an exact-input CALL-to-USDC sell-back:

```text
Q = balanceIn
q = amountIn
require Q + q <= Q0
Qafter = Q + q
```

All other token directions and exact-input/exact-output combinations revert.
The instruction MUST reject `Q > Q0` before doing exposure arithmetic.

## Average-exposure mathematics

CALL quantities use 18 token decimals. Exposure, gamma, and spread use WAD.
For both directions:

```text
soldBefore = Q0 - Q
soldAfter  = Q0 - Qafter
eAvgWad    = floor((soldBefore + soldAfter) * 1e18 / (2 * Q0))
inventoryFactorWad = 1e18 + floor(gammaWad * eAvgWad / 1e18)
```

The `Q0 <= type(uint128).max` bound makes `2 * Q0` safe in `uint256`.
Every multiplication whose full product may exceed 256 bits MUST use the
reviewed `FullMath` implementation.

The average exposure MUST cover the entire inventory transition. Applying only
the starting exposure to a multi-CALL trade is forbidden.

## Register transformation and rounding

Let `B` be the positive total USDC-native amount written by `0xd1`.

For a buy, both adjustment steps round upward:

```text
reservationQuote = ceil(B * inventoryFactorWad / 1e18)
finalQuote       = ceil(reservationQuote * (1e18 + spreadWad) / 1e18)
```

For a sell-back, both adjustment steps round downward:

```text
reservationQuote = floor(B * inventoryFactorWad / 1e18)
finalQuote       = floor(reservationQuote * (1e18 - spreadWad) / 1e18)
```

The buy result replaces `amountIn`; the sell-back result replaces `amountOut`.
The requested CALL register MUST remain unchanged. A result of zero reverts.

This two-stage rule is intentional and MUST be reproduced in Python and later
TypeScript integer vectors. It preserves maker-favorable rounding at each
economic adjustment and avoids an implementation-specific combined factor.

## Integer worked example

For the canonical first one-CALL buy, take the Python fair value and perform
the existing `0xd1` buy conversion first:

```text
B                    = 60,294,027 USDC native units
Q0                   = 10e18
Q                    = 10e18
q                    = 1e18
eAvgWad              = 0.05e18
gammaWad             = 0.20e18
inventoryFactorWad   = 1.01e18
reservationQuote     = ceil(60,294,027 * 1.01) = 60,896,968
spreadWad            = 0.01e18
finalQuote           = ceil(60,896,968 * 1.01) = 61,505,938
```

The existing `black_scholes-v1.json` inventory fields describe the independent
floating-point model with one final settlement rounding. Checkpoint 2 MUST add
a separate versioned integer-pipeline vector document rather than silently
reinterpret or overwrite that schema. Solidity and later TypeScript consume
the new integer document for exact native-unit assertions.

## Final spot cap

`0xd2` reads the bound guarded oracle after identity validation. It derives the
maximum total quote for `q` CALL:

```text
buySpotCap  = ceil(q * spotWad / 1e30)
sellSpotCap = floor(q * spotWad / 1e30)
```

The final quote MUST NOT exceed the direction-specific cap. The oracle's own
window, observation, liquidity, deviation, identity, and price checks remain
authoritative and any failure propagates. The spot read is not a fallback and
does not alter the Black-Scholes input chosen by `0xd1`.

## Instruction-order protection

The missing amount register begins at zero in SwapVM.

- `0xd1` MUST reject a nonzero missing register before writing fair value.
- `0xd2` MUST reject a zero missing register before applying inventory risk.

Therefore `0xd2 -> 0xd1`, a missing `0xd1`, and a second `0xd1` after `0xd2`
fail closed. The canonical builder emits exactly one `0xd1` followed by exactly
one `0xd2`. Because Aqua keys balances by the complete strategy bytes, altered,
duplicated, or extended programs cannot consume liquidity shipped under the
canonical strategy hash.

## Split-execution tolerance

The linear average-exposure model is analytically additive. Integer settlement
adds bounded rounding at three stages: the `0xd1` token conversion, inventory
factor, and spread factor.

For `n` sequential fills compared with one block fill of the same total CALL
quantity and unchanged market/time inputs, the acceptance budget is:

```text
absolute difference <= 3 * (n + 1) USDC native units
```

This conservative bound is `3 * (n + 1)` micro-USDC for a six-decimal quote
token. Tests MUST also prove that a larger buy never receives a better average
ask because of rounding.

## Failure behavior

The instruction MUST revert for:

- malformed argument length or zero address;
- unsupported pair, direction, or exactness mode;
- zero `Q0`, `Q0 > type(uint128).max`, or `Q > Q0`;
- zero CALL quantity or a transition outside `[0, Q0]`;
- gamma above `1e18` or spread above `0.25e18`;
- missing or zero fair-value register;
- oracle base/quote mismatch or any guarded oracle rejection;
- zero final quote, insufficient USDC liquidity, or final quote above spot;
- arithmetic overflow or any impossible fixed-point result.

No fallback quote, clamping of economic parameters, partial inventory fill, or
taker-selected external target is allowed.

## Test acceptance

Tests MUST cover:

- exact 192-byte encoding and canonical opcode assignment;
- all accepted parameter boundaries and one unit outside rejected boundaries;
- zero, partial, and full short exposure;
- first buy, later buy, sell-back, fractional quantity, and multi-unit vectors;
- average exposure and both maker-favorable rounding pipelines;
- buy inventory exhaustion and sell-back above `Q0`;
- current inventory above `Q0` and insufficient quote liquidity;
- zero/missing fair register and reordered instruction failure;
- guarded spot rejection, oracle identity mismatch, and final spot cap;
- unchanged CALL register and absence of token movement or storage mutation;
- first and second identical buys under unchanged strategy bytes, with the
  second ask strictly higher;
- block-versus-split execution inside the native-unit tolerance;
- quote/swap equality and real/virtual Aqua balance reconciliation in both
  directions;
- altered program bytes resolving to an unfunded strategy;
- unchanged pinned submodules and passing upstream suites.

## Temporary opcode retirement

Opcode `0xd0`, its builder, implementation, and dedicated tests were removed
after `0xd1 -> 0xd2` settlement and repricing passed review. Historical commits
and evidence documents remain the record of the deterministic integration
stage.

## Security status

Inventory skew manages a bounded quote curve; it is not a hedge, volatility
surface, solvency guarantee, or manipulation defense. The maker chooses `Q0`,
gamma, and spread and bears that economic configuration risk. Passing tests do
not make the contracts audited or suitable for production or mainnet use.
