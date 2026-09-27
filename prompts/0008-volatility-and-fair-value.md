# Prompt 0008: Add bounded volatility and option fair value

- Date: 2026-09-26
- Input state: guarded Uniswap V3 TWAP adapter and Base Sepolia read-only
  evidence complete
- Authorized scope: volatility registry, fixed-point call math, and fair-value
  SwapVM instruction in separately reviewed checkpoints

## Objective

Replace the temporary proof premium with an explainable Black-Scholes fair
value sourced from the bound Uniswap TWAP adapter, immutable `OptionSeries`
terms, and a separately bounded implied-volatility registry.

This prompt does not authorize inventory skew, spread, TypeScript packages,
frontend work, live deployments, liquidity operations, strategy shipping, or
the removal of the temporary opcode before the production path is proven.

## Pinned math dependency

- PRBMath release: `v4.2.0`
- Commit: `29a3c06c709496a8f9775dea115935befc5158a7`
- License: MIT
- Repository: `https://github.com/PaulRBerg/prb-math`

## Commit checkpoints

### Checkpoint 1 — Architecture and dependency decision

Specify the volatility trust boundary, immutable updater, accepted value and
freshness domains, CDF approximation, Black-Scholes bounds, exact opcode
encoding, rounding rules, PRBMath revision, failure paths, and test gates.

Suggested commit:

```text
docs: define volatility and fair-value architecture
```

Stop for review and a human-created commit before installing or writing code.

### Checkpoint 2 — Bounded volatility registry

Implement the immutable-updater registry and focused tests for authorization,
series identity, value bounds, timestamps, events, unconfigured reads, and the
absence of token custody or arbitrary calls.

Suggested commit:

```text
feat: add bounded volatility registry
```

Stop for review and a human-created commit before fixed-point math.

### Checkpoint 3 — Fixed-point CDF and Black-Scholes

Install the exact PRBMath revision without modifying it. Implement the bounded
normal CDF and zero-rate European-call library. Extend the independently
generated vectors as needed, then test accuracy, monotonicity, domains,
intrinsic boundaries, and fair-value invariants.

Suggested commit:

```text
feat: add fixed-point Black-Scholes pricing
```

Stop for review and a human-created commit before changing router dispatch.

### Checkpoint 4 — Fair-value opcode and settlement evidence

Implement opcode `0xd1`, its canonical builder, oracle/series/volatility
validation, direction-specific token rounding, dispatcher wiring, and local
Aqua settlement tests for buy and sell-back fair value. Preserve `0xd0` only as
clearly labeled test scaffolding until the later inventory path replaces it.

Suggested commit:

```text
feat: execute option fair value through SwapVM
```

## Exit gate

- volatility updates are bounded, timestamped, emitted, and administrator-only;
- pricing reads only strategy-bound contracts through static calls;
- CDF and fair value meet the committed cross-language tolerances;
- expired, stale, future-dated, missing, zero, excessive, and malformed inputs
  fail closed;
- quote and swap agree and settle through Aqua without opcode token movement;
- no inventory or spread behavior is smuggled into fair value;
- pinned dependencies remain exact and their upstream tests stay green.

## Repository boundary

Do not stage files, create commits, deploy contracts, submit forms, or push to a
remote repository. Each checkpoint stops for human review and commit creation.
