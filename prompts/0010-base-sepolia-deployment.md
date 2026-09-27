# Prompt 0010: Prepare and execute the Base Sepolia deployment

- Date: 2026-09-26
- Input state: inventory-aware Aqua settlement is implemented and tested;
  temporary pricing scaffolding is retired
- Authorized scope: deployment architecture, test-token and deployment tooling,
  deterministic fork rehearsal, separately approved Base Sepolia broadcasts,
  verification, and public evidence

## Objective

Publish a reproducible Base Sepolia AquaVol market that writes a fully
collateralized CALL, ships maker liquidity through official Aqua contracts,
prices it with the modified SwapVM router, and records a real CALL/DemoUSDC
trade with reconciled token and virtual-balance changes.

This prompt does not authorize frontend implementation, production use,
mainnet assets, undisclosed administrator assumptions, or an unreviewed live
broadcast. It never authorizes committing a secret, populated `.env`, keystore,
mnemonic, or raw signed transaction.

## Operational identity model

The hackathon deployment uses two testnet-only identities:

1. The **operator wallet** deploys contracts and acts as volatility updater,
   option writer, and Aqua maker. Consolidating these roles is a disclosed
   Base Sepolia operational simplification, not a production security model.
2. The **trader wallet** connects through a browser wallet and remains separate
   so public transfers and balance changes have an independent counterparty.

Only the operator requires deployment signing configuration. Its private key
MUST stay in ignored local configuration or an encrypted Foundry keystore. The
trader private key MUST NOT be stored in the repository. Both wallets need
Base Sepolia ETH for their own transactions. Neither wallet may hold mainnet
funds or be reused as a production identity.

The operator can update implied volatility and therefore influence quotes. It
cannot seize trader balances, move OptionSeries collateral outside the
specified lifecycle, or bypass Aqua settlement. The README, UI, and deployment
manifest MUST disclose the consolidated role.

## Commit checkpoints

### Checkpoint 1 — Deployment architecture and safety boundary

Specify the chain, official protocol dependencies, wallet roles, asset profile,
ordered deployment graph, environment-variable names, manifest schema,
preflight checks, broadcast gates, verification evidence, and rollback limits.
Correct stale implementation-status documentation. Do not add scripts, deploy
contracts, mint assets, initialize pools, or broadcast transactions.

Suggested commit:

```text
docs: define Base Sepolia deployment architecture
```

Stop for review and a human-created commit before deployment tooling.

### Checkpoint 2 — Deployment contracts and preflight tooling

Add the clearly labeled DemoUSDC test token, narrow interfaces needed for the
official Uniswap V3 deployment, Foundry deployment configuration, and a
read-only preflight script. Test access control, decimals, minting bounds,
dependency ordering, chain-ID rejection, missing-code rejection, and manifest
input validation. The script MUST not broadcast in its default mode.

Suggested commit:

```text
feat: add Base Sepolia deployment tooling
```

Stop for review and a human-created commit before rehearsal.

### Checkpoint 3 — Deterministic fork rehearsal

On a pinned Base Sepolia fork, rehearse the complete deployment and market
bootstrap. Create and initialize WETH/DemoUSDC liquidity, prove the configured
TWAP can mature, deploy the AquaVol graph, write CALL, ship Aqua balances, set
volatility, and settle a maker/trader trade. Produce a reviewable dry-run
summary without modifying public chain state.

Suggested commit:

```text
test: rehearse Base Sepolia market deployment
```

Stop for review and a human-created commit before any public broadcast.

### Checkpoint 4 — Staged Base Sepolia broadcast

Broadcast only after the human reviews the exact chain ID, signer address,
balance, constructor arguments, pool price, liquidity amounts, option terms,
and simulation output. Split infrastructure deployment, pool bootstrap,
protocol deployment, and strategy preparation into recoverable stages. Record
transaction hashes and addresses after each confirmed stage. Never source or
print secret values in logs.

Suggested commit:

```text
deploy: publish AquaVol on Base Sepolia
```

Stop for review and a human-created commit before the public trade.

### Checkpoint 5 — Public trade and evidence

Settle a trader transaction through Aqua, then capture explorer links, events,
real token changes, Aqua virtual-balance changes, inventory-driven repricing,
source verification, and a read-only manifest check. Add the Uniswap
`FEEDBACK.md` requirement and direct README pointers to the integration code.

Suggested commit:

```text
docs: record Base Sepolia deployment evidence
```

## Exit gate

- every address resolves to deployed code on chain ID `84532`;
- official Uniswap addresses are revalidated against an official source at
  execution time;
- the official Aqua implementation and the source-disclosed modified SwapVM
  router are identifiable from the manifest;
- DemoUSDC and the project-seeded pool are unmistakably labeled as test assets;
- OptionSeries collateral equals outstanding written exposure;
- the public trade reconciles trader, maker, and Aqua real/virtual balances;
- the same strategy bytes produce the expected inventory-driven next quote;
- contracts, constructor arguments, source commit, compiler settings,
  transaction hashes, and verification status are recorded;
- no secret or populated local configuration is tracked by Git;
- a deterministic local-fork fallback remains runnable.

## Repository boundary

Do not stage files, create commits, submit forms, or push to a remote
repository. No live transaction may be broadcast without an explicit human
instruction for that individual deployment stage.
