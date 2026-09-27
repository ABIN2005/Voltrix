# Prompt 0011: Build the AquaVol strategy workspace

- Date: 2026-09-26
- Input state: the Base Sepolia Aqua market and distinct-trader settlement are
  publicly demonstrated
- Authorized scope: frontend specification, original React/TypeScript/Vite
  interface, local option simulation, and links to existing public evidence

## Objective

Create an original, demo-ready frontend that explains and visualizes AquaVol's
programmable option position. Use the interaction lessons from the local
options reference only where they fit AquaVol; do not carry over exchange data,
branding, layout, market assumptions, server code, or Black-76 calculations.

## Checkpoint 1 — Frontend foundation

Add the specification, React/TypeScript/Vite application, original visual
tokens, public deployment snapshot, option-leg types, zero-rate Black-Scholes
simulation, and a minimal responsive shell. The checkpoint must build without
requiring a wallet or RPC connection.

Suggested commit:

```text
feat: scaffold AquaVol frontend foundation
```

Stop for review and a human-created commit.

## Checkpoint 2 — Strategy builder and strike ladder

Add editable option legs, strategy presets, expiry selection, and a responsive
CALL/PUT strike ladder. Clearly distinguish the single live series from all
simulated strikes, expiries, and PUTs.

Suggested commit:

```text
feat: add option strategy builder
```

Stop for review and a human-created commit.

## Checkpoint 3 — Interactive payoff visualization

Add the expiration payoff chart, profit and loss regions, TWAP and strike
markers, hover values, premium, breakeven, and payoff-bound metrics.

Suggested commit:

```text
feat: visualize multi-leg option payoffs
```

Stop for review and a human-created commit.

## Checkpoint 4 — Protocol proof and responsive polish

Add the Uniswap-to-Aqua integration flow, BaseScan links, public trade evidence,
inventory repricing, final visual polish, and complete mobile behavior.

Suggested commit:

```text
feat: present AquaVol onchain proof
```

Stop for review and a human-created commit. Do not stage, commit, push, or
broadcast transactions in any frontend checkpoint.

## Checkpoint 5 — Live application integration

After review, replace deployment snapshots with guarded Base Sepolia reads,
add browser-wallet connection, construct live quotes, request bounded approvals,
and execute only the deployed CALL through the AquaVol router. Simulated legs
must remain visibly non-executable.

Suggested commit:

```text
feat: connect live AquaVol trading
```

## Exit gate

- the frontend follows `specs/12-frontend-strategy-workspace.md`;
- its live labels agree with the public deployment evidence;
- simulated instruments cannot be confused with executable inventory;
- no secret or signing material enters the frontend;
- repository staging, commits, and pushes remain human-controlled.
