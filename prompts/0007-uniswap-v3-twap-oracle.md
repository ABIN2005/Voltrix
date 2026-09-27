# Prompt 0007: Add the Uniswap V3 TWAP spot oracle

- Date: 2026-09-26
- Input state: completed custom SwapVM routing and local Aqua settlement
- Authorized scope: guarded spot-price adapter and read-only Base Sepolia evidence

## Objective

Replace the trusted mock spot input with an immutable Uniswap V3 TWAP adapter
that can later feed the AquaVol fair-value opcode. Preserve volatility as a
separate bounded input and keep pricing mathematics outside this phase.

This prompt does not authorize Solidity Black-Scholes, volatility-registry
implementation, inventory skew, live deployment transactions, frontend work,
or changes to the pinned Aqua and SwapVM submodules.

## Pinned references

- Uniswap V3 core: `d0831dc6b8a318df3872b6d68f6de135c9f3ec29`
- Uniswap V3 periphery: `0682387198a24c7cd63566a2c58398533860a5d1`
- Uniswap SDK address registry: `60d7e07e9dd1c62a8b662effd1818c24c5e02ebc`

## Commit checkpoints

### Checkpoint 1 — Architecture, provenance, and deployment profile

Record the immutable oracle interface, validation rules, live Base Sepolia
findings, official source revisions, license boundary, deterministic demo-pool
profile, and explicit non-goals.

Suggested commit:

```text
docs: define Uniswap V3 TWAP oracle architecture
```

Stop for review and a human-created commit before writing oracle code.

### Checkpoint 2 — Guarded adapter and local tests

Implement the minimal Solidity 0.8.30 adapter and only the upstream-derived
math required for V3 TWAP conversion. Add controllable pool/factory doubles and
unit tests for signed rounding, token order, decimals, liquidity, history,
latest-observation age, deviation, identity, and numeric bounds.

Suggested commit:

```text
feat: add guarded Uniswap V3 TWAP oracle
```

Stop for review and a human-created commit before network verification.

### Checkpoint 3 — Base Sepolia read-only evidence

Add an opt-in verification script or fork test that resolves the canonical
WETH/test-USDC pools from the official factory and records observable pool
state. It MUST perform no deployment, pool mutation, liquidity operation, or
swap. Default offline tests must remain independent of RPC availability.

Suggested commit:

```text
test: verify Uniswap oracle against Base Sepolia
```

## Exit gate

- the adapter is immutable, view-only, and fails closed;
- spot is derived from the complete TWAP window rather than `slot0`;
- pool identity, observations, liquidity, decimals, direction, and bounds are
  covered by tests;
- adapted upstream code is pinned, attributed, and correctly licensed;
- Base Sepolia evidence is reproducible without becoming a default test
  dependency;
- existing AquaVol, Python, Aqua, and SwapVM suites remain green.

## Repository boundary

Do not stage files, create commits, deploy contracts, submit forms, or push to a
remote repository. Each checkpoint must stop for human review and commit
creation.
