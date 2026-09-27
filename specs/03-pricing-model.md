# Pricing model specification

## Status

- Version: 0.5
- State: reference math, guarded spot, bounded volatility, fair value, inventory
  adjustment, spread, and bidirectional settlement implemented and tested
- Implementation authorized: Prompt 0010 may consume the implemented pricing
  path for review-gated Base Sepolia deployment

## Scope

The pricing path combines:

```text
Black-Scholes call fair value
          +
Aqua CALL inventory adjustment
          +
maker half-spread
          =
executable bid or ask
```

The pricing path does not determine exercise eligibility or collateral.

## Black-Scholes assumptions

The MVP prices a European call with:

- risk-free rate `r = 0`;
- continuous dividend yield `q = 0`;
- positive spot `S`;
- positive strike `K`;
- annualized implied volatility `sigma`;
- time to expiry `T` expressed in years.

For an active series:

```text
d1 = (ln(S / K) + 0.5 * sigma^2 * T) / (sigma * sqrt(T))
d2 = d1 - sigma * sqrt(T)
C  = S * N(d1) - K * N(d2)
```

Time is calculated as:

```text
T = (expiry - block.timestamp) / 365 days
```

The math library MUST define these boundary results even though active-market
execution rejects expired inputs:

```text
T == 0       => max(S - K, 0)
sigma == 0   => max(S - K, 0)
```

The active runtime oracle policy MAY reject zero volatility.

## Numeric representations

- Prices, volatility, time-in-years, CDF values, gamma, exposure, and spread
  use 18-decimal fixed point.
- CALL amounts use 18 token decimals.
- USDC settlement amounts use 6 token decimals.
- Timestamps use integer seconds.
- Signed intermediate values are required for `ln(S/K)`, `d1`, and `d2`.

All multiplication and division that can overflow a 256-bit intermediate MUST
use a reviewed full-precision routine. Naive `(a * b) / denominator` arithmetic
is not acceptable without a proven input bound that prevents overflow.

## Supported input domain

The initial implementation MUST choose and enforce bounds no wider than:

| Input | Required MVP domain |
| --- | --- |
| Spot | `(0, 1_000_000]` quote units |
| Strike | `(0, 1_000_000]` quote units |
| Time | `(0, 366 days]` for active trading |
| Volatility | `(0, 5.0]`, representing up to 500% |
| `d1`, `d2` CDF evaluation | Saturate at or outside `[-8, 8]` |
| Inventory gamma | `[0, 1.0]` |
| Half-spread | `[0, 0.25]` |

The implementation MAY narrow these bounds. Tests MUST cover every boundary and
one unit outside each rejected boundary.

## Normal CDF

`N(x)` MAY use a bounded approximation. It MUST:

- return a value in `[0, 1e18]`;
- preserve `N(-x) = 1 - N(x)` within fixed-point rounding tolerance;
- be monotonically nondecreasing;
- saturate safely for extreme inputs;
- document coefficients and their source;
- avoid overflow and unsupported exponential domains.

Initial acceptance targets, subject to validation before approval:

- maximum absolute CDF error of `2e-6` over `[-8, 8]` against the Python
  reference;
- monotonic output across the generated test grid.

## Fair-value bounds

For the zero-rate call model:

```text
max(S - K, 0) <= C <= S
```

The implementation MUST preserve these bounds after numerical approximation.
A computed value outside them MUST be clamped only if the underlying error is
understood and tested; otherwise execution MUST revert.

## Canonical reference vector

The initial public example is:

| Input | Value |
| --- | --- |
| Spot | 3,800 |
| Strike | 4,000 |
| Time | 7 / 365 years |
| Volatility | 0.64 |
| Risk-free rate | 0 |
| Dividend yield | 0 |

Expected fair value is approximately `60.29` quote units. The generated Python
vector, including additional precision, becomes canonical before Solidity tests
are written.

The canonical market-making parameters are:

```text
Q0          = 10 CALL
Q           = 10 CALL before the first purchase
q           = 1 CALL
gamma       = 0.20
half-spread = 0.01
```

The first purchase integrates exposure from `0%` to `10%`, so its average
exposure is `5%`. Its reference ask is therefore approximately:

```text
fair * (1 + 0.20 * 0.05) * (1 + 0.01)
```

The generated vector supplies the canonical precise value.

Initial option-price tolerance is the larger of:

- `0.10` quote units; or
- `10` basis points of the Python reference premium.

This tolerance covers only the mathematical approximation. Token conversion and
maker-favorable settlement rounding are tested separately.

## Oracle inputs

The fair-value instruction MUST obtain:

- spot from the strategy-bound Uniswap V3 TWAP adapter, including its averaging
  window, latest initialized observation time, and liquidity result;
- implied volatility and volatility update timestamp.

It MUST reject:

- zero spot;
- spot or volatility outside the approved domain;
- an update timestamp in the future beyond a small documented clock tolerance;
- a Uniswap pool whose latest initialized observation is older than
  `maxObservationAge` or whose history cannot cover the TWAP window;
- harmonic-mean liquidity below the strategy-bound minimum;
- volatility older than `maxVolatilityAge`;
- trading at or after expiry.

Spot and volatility SHOULD have separate freshness limits.

## Inventory model

Let:

- `Q0` be initial shipped CALL inventory;
- `Q` be current Aqua CALL inventory;
- `q` be the trade CALL quantity;
- `gamma` be the inventory-risk coefficient;
- `spread` be the half-spread;
- `P` be Black-Scholes fair value.

Current short-exposure ratio is:

```text
e = (Q0 - Q) / Q0
```

The MVP MUST maintain `0 <= Q <= Q0` and therefore `0 <= e <= 1`.

### Exact-output buy

For a trader buying `q` CALL:

```text
Qafter = Q - q
e0     = (Q0 - Q) / Q0
e1     = (Q0 - Qafter) / Q0
eAvg   = (e0 + e1) / 2

reservation = P * (1 + gamma * eAvg)
ask         = reservation * (1 + spread)
```

USDC input MUST round upward in the maker's favor.

### Exact-input sell-back

For a trader selling `q` CALL back:

```text
Qafter = Q + q
require Qafter <= Q0

e0          = (Q0 - Q) / Q0
e1          = (Q0 - Qafter) / Q0
eAvg        = (e0 + e1) / 2

reservation = P * (1 + gamma * eAvg)
bid         = reservation * (1 - spread)
```

USDC output MUST round downward in the maker's favor.

The executable bid and ask MUST remain positive. A final premium above spot or
outside configured safety bounds MUST make the quote unavailable rather than
silently create an economically invalid value.

## Order-size integration

The price of a multi-CALL trade MUST use average exposure across the full
inventory transition. Pricing the entire trade at starting inventory is
forbidden.

For unchanged oracle and time inputs, one trade of quantity `q` SHOULD match a
sequence of smaller trades totaling `q`, with any difference bounded by the
documented accumulation of token-unit rounding.

## Cross-language vector format

Python SHOULD generate versioned JSON containing:

- model version;
- inputs in human-readable decimal strings;
- normalized integer inputs;
- `d1`, `d2`, CDF values, and fair value;
- expected bid and ask for selected inventory states;
- tolerance fields;
- edge-case classification.

Python, Solidity, and TypeScript MUST consume the same committed vectors rather
than maintain independently typed expected values.

## Required vector families

Vectors MUST cover:

- deep in-, at-, and out-of-the-money calls;
- one hour, one day, seven days, thirty days, and boundary expiry;
- low, ordinary, high, zero, and rejected excessive volatility;
- CDF tails and symmetry;
- fractional CALL quantities;
- zero, partial, and full short exposure;
- buy and sell-back rounding;
- a multi-unit trade compared with split execution.

## Resolved by Prompt 0008 architecture

- PRBMath `v4.2.0` at commit
  `29a3c06c709496a8f9775dea115935befc5158a7` is the selected fixed-point
  dependency.
- The normal CDF uses the bounded Abramowitz and Stegun 26.2.17 approximation
  and retains the `2e-6` measured-error gate.
- Spot, strike, time, and volatility bounds are fixed by
  `specs/09-volatility-and-fair-value.md`; gamma and spread remain deferred to
  the inventory prompt.
- A mathematical call value may equal spot, but runtime pricing rejects zero or
  out-of-domain premiums and later inventory pricing must reject a final quote
  above its safety bound.

These items remain deliberately unresolved for Solidity. They do not block the
standard-library Python reference, which uses binary floating-point calculations
and `math.erf` for the normal CDF.
