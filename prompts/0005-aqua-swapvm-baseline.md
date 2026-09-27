# Prompt 0005: Establish the Aqua and SwapVM baseline

- Date: 2026-09-26
- Input state: tested OptionSeries lifecycle and approved integration specification
- Authorized scope: dependency provenance and one unmodified local Aqua/SwapVM swap

## Objective

Prove the official protocol execution path before adding AquaVol pricing logic.
The baseline must ship virtual token balances, execute one swap through the
unmodified Aqua and SwapVM contracts, and reconcile real token transfers with
Aqua's virtual balances.

This prompt does not authorize custom opcodes, Black-Scholes Solidity,
inventory skew, or Base Sepolia deployment.

## Pinned upstream revisions

- Aqua: `1inch/aqua` at `ef24220ed9647555727b06867bf509cd6959d84b`
- SwapVM: `1inch/swap-vm` at `feb16411738331f7d05ae71d4a664154068018fc`
- Aqua SDK reference: `1inch/sdks` at
  `3dbd4fd17fdc9fb814b8d55b3efcf4a39eddb32c`

No dependency may follow a moving branch after it is introduced. Preserve all
upstream license, copyright, and third-party notices.

## Commit checkpoints

### Checkpoint 1 — Specification and provenance

Create the prompt record, pin exact revisions, record licenses and attribution
requirements, and approve only the unmodified local baseline.

Suggested commit:

```text
docs: define Aqua SwapVM baseline integration
```

Stop for review and a human-created commit before importing protocol code.

### Checkpoint 2 — Pinned protocol harness

Import only the files required for the baseline at the approved revisions.
Record the import mechanism and file inventory. Configure Foundry remappings,
deploy the official contracts locally, and prove that their upstream baseline
tests compile and pass without modification.

Suggested commit:

```text
build: add pinned Aqua and SwapVM test harness
```

Stop for review and a human-created commit before writing the AquaVol
integration test.

### Checkpoint 3 — Unmodified swap evidence

Create a local integration test using mock 18-decimal CALL and 6-decimal USDC.
The test must:

1. fund maker and trader actors;
2. approve the official Aqua contract;
3. encode one canonical strategy byte sequence;
4. ship CALL and USDC virtual balances;
5. execute one supported unmodified SwapVM swap;
6. assert maker, trader, and Aqua virtual-balance deltas;
7. assert that OptionSeries collateral is unchanged;
8. reject altered strategy bytes and insufficient liquidity.

Suggested commit:

```text
test: reproduce unmodified Aqua SwapVM settlement
```

## Exit gate

- upstream revisions and licenses are reproducible from repository records;
- upstream contracts compile without local source edits;
- the same strategy bytes determine shipping, balance lookup, and execution;
- one successful swap reconciles all real and virtual balance changes;
- failure cases revert without partial settlement;
- existing OptionSeries and Python tests remain green.

## Repository boundary

Do not stage files, create commits, or push to a remote repository. Each
checkpoint must stop for human review and commit creation.
