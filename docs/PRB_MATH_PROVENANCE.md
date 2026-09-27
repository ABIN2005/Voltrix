# PRBMath provenance

## Pinned dependency

| Field | Value |
| --- | --- |
| Repository | `https://github.com/PaulRBerg/prb-math` |
| Release | `v4.2.0` |
| Commit | `29a3c06c709496a8f9775dea115935befc5158a7` |
| License | MIT |
| Local path | `contracts/lib/prb-math` |

The dependency is installed as an unmodified Git submodule. Its upstream
license, notices, source, tests, and history remain inside that submodule.

## Imported surface

AquaVol imports the specific `SD59x18` type and `sd` wrapper through:

```text
@prb/math/src/SD59x18.sol
```

The compiler follows PRBMath's own internal imports for signed fixed-point
logarithm, exponential, multiplication, division, and square root. AquaVol does
not copy or modify those implementations.

## Usage boundary

PRBMath supplies deterministic fixed-point primitives only. AquaVol remains
responsible for:

- input bounds and unit conventions;
- the normal-CDF approximation and its measured error;
- Black-Scholes model assumptions;
- analytical fair-value bounds;
- strategy, oracle, freshness, and settlement validation.

The dependency's audit history and upstream test coverage do not constitute an
audit of AquaVol or make the option-pricing model production-ready.
