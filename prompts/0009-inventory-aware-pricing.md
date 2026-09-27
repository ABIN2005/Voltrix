# Prompt 0009: Add inventory-aware option pricing

- Date: 2026-09-26
- Input state: bounded fair-value opcode and bidirectional Aqua settlement complete
- Authorized scope: inventory mathematics, opcode `0xd2`, dynamic repricing
  evidence, and retirement of the temporary constant-price opcode in separately
  reviewed checkpoints

## Objective

Compose live Aqua CALL balances with the existing `OPTION_FAIR_VALUE`
instruction so the executable option price reflects the maker's average short
exposure across each trade. The canonical program must visibly reprice without
changing its strategy bytes after inventory changes.

This prompt does not authorize TypeScript packages, frontend work, public
deployment transactions, live liquidity operations, volatility-model changes,
or changes to the pinned Aqua, SwapVM, or PRBMath submodules.

## Economic bounds

- initial CALL inventory `Q0`: `(0, type(uint128).max]` token-native units;
- inventory gamma: `[0, 1e18]`;
- half-spread: `[0, 0.25e18]`;
- current and post-trade CALL inventory: `[0, Q0]`;
- final executable premium: positive and no greater than the guarded spot cap.

The canonical demo continues to use `Q0 = 10e18`, `gamma = 0.20e18`, and
`halfSpread = 0.01e18`.

## Commit checkpoints

### Checkpoint 1 — Inventory architecture

Specify exact opcode encoding, live Aqua balance selection, average-exposure
arithmetic, fixed-point rounding, spot-cap validation, instruction ordering,
failure paths, split-trade tolerance, and test gates.

Suggested commit:

```text
docs: define inventory-aware pricing architecture
```

Stop for review and a human-created commit before writing inventory Solidity.

### Checkpoint 2 — Fixed-point inventory mathematics

Add a versioned integer inventory-settlement vector document and implement a
storage-free Solidity inventory library. Test all committed inventory cases,
accepted boundaries, one-unit rejected boundaries, monotonicity, average
exposure, buy/sell rounding, and block-versus-split execution.

Suggested commit:

```text
feat: add fixed-point inventory pricing
```

Stop for review and a human-created commit before router dispatch changes.

### Checkpoint 3 — Inventory opcode

Implement the canonical `0xd2` builder and dispatcher path. Add the `0xd1`
missing-register guard required for order enforcement. Validate the bound pair,
oracle identity, modes, current inventory, post-trade inventory, fair-value
register, economic parameters, final quote, and spot cap.

Suggested commit:

```text
feat: execute inventory pricing through SwapVM
```

Stop for review and a human-created commit before end-to-end settlement work.

### Checkpoint 4 — Dynamic Aqua repricing

Prove exact-output buys and exact-input sell-backs through Aqua. Demonstrate
that the same unchanged strategy produces a higher next ask after a buy,
multi-unit and sequential fills agree within the declared native-unit rounding
budget, altered strategy bytes cannot use shipped balances, and every real and
virtual balance delta reconciles.

Suggested commit:

```text
test: prove inventory-driven Aqua repricing
```

Stop for review and a human-created commit before removing integration
scaffolding.

### Checkpoint 5 — Retire constant-price scaffolding

Remove opcode `0xd0`, its builder, implementation, and dedicated settlement
tests. Keep the historical evidence in Git and documentation, then rerun all
project and upstream protocol verification.

Suggested commit:

```text
refactor: retire constant-price pricing scaffold
```

## Exit gate

- the canonical program composes `0xd1` followed by exactly one `0xd2`;
- live Aqua CALL balances determine average exposure;
- buys cannot exceed current CALL inventory;
- sell-backs cannot raise CALL inventory above `Q0`;
- gamma, spread, inventory, direction, mode, and final price fail closed;
- identical later buys become more expensive after CALL inventory decreases;
- block and split execution differ only within the documented rounding budget;
- quote and swap agree and settle through Aqua without opcode token movement;
- temporary constant-price execution is absent from the final router;
- pinned dependencies remain exact and their upstream tests stay green.

## Repository boundary

Do not stage files, create commits, deploy contracts, submit forms, or push to a
remote repository. Each checkpoint stops for human review and commit creation.
