# Prompt 0006: Add the custom SwapVM foundation

- Date: 2026-09-26
- Input state: accepted pinned Aqua/SwapVM baseline with reconciled settlement
- Authorized scope: isolated modified router and one deterministic proof opcode

## Objective

Prove that an AquaVol instruction can execute through a modified SwapVM router
while preserving official Aqua settlement and unaffected upstream behavior.
Separate custom dispatch mechanics from option mathematics so later failures
can be attributed to the correct layer.

This prompt does not authorize Black-Scholes Solidity, inventory skew, oracle
contracts, TypeScript encoding, frontend work, or public deployment.

## Fixed decisions

- Keep `contracts/lib/aqua` and `contracts/lib/swap-vm` unchanged.
- Extend the pinned dispatcher and delegate unaffected opcodes to `super`.
- Allocate `0xd0` to temporary `AQUAVOL_CONSTANT_PRICE`.
- Reserve `0xd1` for `OPTION_FAIR_VALUE`.
- Reserve `0xd2` for `OPTION_INVENTORY_SKEW`.
- Never allocate the upstream-reserved `0xf0–0xff` bank.
- Add no custom persistent router storage.
- Let opcodes calculate register values only; Aqua performs token settlement.
- License derivative SwapVM extension files under
  `LicenseRef-Degensoft-SwapVM-1.1` with required notices and marked changes.

## Commit checkpoints

### Checkpoint 1 — Architecture and opcode allocation

Record the custom-router boundary, canonical opcode values, instruction format,
license obligations, delegation rule, and test gates. Update status documents
that still describe the completed protocol baseline as future work.

Suggested commit:

```text
docs: define custom SwapVM opcode architecture
```

Stop for review and a human-created commit before writing derivative code.

### Checkpoint 2 — Router and deterministic opcode

Implement the AquaVol dispatcher, router, raw instruction builder, and the
temporary constant-price instruction. Add focused unit tests for encoding,
dispatch delegation, malformed inputs, unsupported modes, and reserved values.

Suggested commit:

```text
feat: add AquaVol SwapVM router and deterministic opcode
```

Stop for review and a human-created commit before integration testing.

### Checkpoint 3 — Compatibility and settlement evidence

Run the modified router through the canonical CALL/USDC Aqua flow. Prove the
fixed premium controls settlement, real and virtual balance changes reconcile,
OptionSeries collateral is isolated, safety failures are atomic, and one
unaffected upstream program retains its behavior.

Suggested commit:

```text
test: verify custom router preserves upstream settlement
```

## Exit gate

- upstream submodules remain pinned and clean;
- custom instruction bytes have one canonical mapping;
- custom dispatch is isolated and unaffected instructions delegate upstream;
- custom opcodes do not move tokens or add storage;
- quote and execution agree through official Aqua settlement;
- derivative source and attribution meet the recorded license obligations;
- all existing Python, OptionSeries, upstream, and integration tests pass.

## Repository boundary

Do not stage files, create commits, or push to a remote repository. Each
checkpoint must stop for human review and commit creation.
