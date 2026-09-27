# AquaVol

AquaVol is a spec-driven project being developed during ETHGlobal Tokyo 2026.

## Status

This repository contains the project specifications and prompt record, an
independent Python mathematical reference, the collateralized option lifecycle,
and a pinned local Aqua/SwapVM integration harness. The unmodified protocol
baseline settles a tested CALL/USDC trade and reconciles real token transfers
with Aqua virtual balances.

The **custom SwapVM router, local Aqua settlement path, guarded Uniswap V3 TWAP
spot oracle, bounded volatility registry, fixed-point Black-Scholes libraries,
fair-value opcode, inventory-skew opcode, and dynamic Aqua repricing are
implemented and tested**. Base Sepolia canonical-pool verification, deployment
preflight tooling, and a pinned full-deployment fork rehearsal are available.
A partial Base Sepolia deployment now includes the demo asset, seeded Uniswap
V3 pool, exact-source Aqua, size-safe custom SwapVM router and pricing engine,
volatility registry, guarded TWAP oracle, immutable option series, and a live
fully collateralized Aqua strategy. A distinct trader has completed the public
0.01 CALL purchase with reconciled real and virtual balances. Source
verification and final submission checks remain pending. The browser strategy
workspace now includes live Base Sepolia reads, a strike ladder, multi-leg
payoffs, and public settlement evidence. No backend is required for the demo.

## Intended stack

- Frontend: React, TypeScript, and Vite
- Backend: Node.js and TypeScript
- Smart contracts: Solidity and Foundry
- Network: Base Sepolia
- Reference mathematics: Python Black-Scholes model and deterministic test
  vectors

## How it works

```mermaid
flowchart TD
    A[Alice / Writer and Maker]
    B[Bob / Trader]
    O[OptionSeries]
    AQ[Aqua Virtual Balances]
    VM[Modified SwapVM]
    S[Updated Aqua Strategy State]

    A -->|Lock 0.10 WETH| O
    O -->|Mint 0.10 CALL| A

    A -.->|Approve CALL and USDC| AQ
    A -.->|Ship virtual CALL and USDC balances| AQ

    B -->|Request CALL quote| VM
    VM -->|Read safeBalances| AQ
    AQ -->|Current CALL and USDC balances| VM
    VM -->|Fair value plus inventory skew and spread| B

    A -->|0.01 CALL settled through Aqua pull| B
    B -->|Quoted USDC settled through Aqua push| A

    AQ -->|CALL decreases and USDC increases| S
    S -->|Changes the next quote| VM

    B -->|Optional sell-back through Aqua push| A
    A -->|Bid USDC through Aqua pull| B

    B -->|During exercise window: CALL and strike USDC| O
    O -->|Burn the exercised CALL| O
    O -->|Send WETH| B
```

`OptionSeries` holds collateral and enforces exercise. Aqua tracks the maker's
virtual liquidity and settles token transfers. SwapVM reads the current Aqua
balances and calculates the executable price. The solid maker/trader arrows
show economic token movement authorized and accounted for through Aqua; Aqua
does not custody the strategy inventory when it is shipped.

## Live Base Sepolia deployment

The complete public settlement proof is live on Base Sepolia (`84532`). All
assets and liquidity are hackathon-only test infrastructure.

| Component | Address |
| --- | --- |
| AquaVol Demo USD (`avUSD`) | [`0xf475...A9dc`](https://sepolia.basescan.org/address/0xf47584005b5c0F90f292C811016E70e37E3BA9dc) |
| WETH/avUSD Uniswap V3 pool | [`0x0d95...6D0`](https://sepolia.basescan.org/address/0x0d9516aA182Aa72284802372afaa943E9E77A6D0) |
| Exact-source Aqua | [`0x170B...4F9`](https://sepolia.basescan.org/address/0x170B0d7C534785eAD9Ecbc278B3D87781855D4F9) |
| AquaVol pricing engine | [`0x68b7...4884`](https://sepolia.basescan.org/address/0x68b7036ae9e1266675f226F36d2c764927C84884) |
| Modified SwapVM router | [`0x8b73...ceb4`](https://sepolia.basescan.org/address/0x8b734D9222D51Aa75C038AB81145FC86D5b4ceb4) |
| Volatility registry | [`0xF253...C37e`](https://sepolia.basescan.org/address/0xF2537463ddeA54EEa205bD183a9e303bDe02C37e) |
| Guarded TWAP oracle | [`0x2D2b...8903`](https://sepolia.basescan.org/address/0x2D2bfade5AD73C946fdcA2a882A21E542A568903) |
| WETH 4,000 CALL series | [`0x7F3c...A117`](https://sepolia.basescan.org/address/0x7F3c414aEf81CAf377fF34A419EC388105fBA117) |

The distinct trader's [`0.01 CALL` purchase](https://sepolia.basescan.org/tx/0xb49b7574aa15a92cb96fb6b804279ca321488dcd1b43a8c6bb780a9dd1cf7379)
paid 0.779818 avUSD. The unchanged strategy then quoted 0.815649 avUSD for the
next 0.01 CALL because live Aqua inventory fell from 0.10 to 0.09 CALL.
OptionSeries retained the full 0.10 WETH collateral throughout settlement.

See the [complete deployment evidence](docs/BASE_SEPOLIA_DEPLOYMENT.md) for
constructor settings, transaction sequence, balance reconciliation, strategy
hash, trust assumptions, and reproducible verification commands.

## Frontend strategy workspace

The [`frontend`](frontend/README.md) application includes editable four-leg
CALL/PUT strategies, explicit `LIVE` versus `SIM` instruments, an interactive
payoff diagram, Base Sepolia contract reads, and direct public-evidence links.
Only the deployed WETH 4,000 CALL expiring 2026-10-04 is labelled live.

```bash
cd frontend
npm install
npm run build
npm run dev
```

## Mathematical reference

The standard-library Python model provides independent Black-Scholes and
inventory-pricing vectors for later TypeScript and Solidity implementations.
For the canonical inputs—3,800 spot, 4,000 strike, seven days, and 64%
volatility—the fair call value is `60.294026671319` USDC. With the approved
first-trade inventory adjustment and spread, the initial one-CALL ask is
`61.505936607413` USDC before token-unit rounding.

Run the reference tests from the repository root:

```bash
PYTHONPATH=python python3 -m unittest discover -s python/tests -v
```

See the [Python reference](python/README.md) and
[version-one vectors](test/vectors/black_scholes-v1.json).

## OptionSeries contracts

The Foundry project implements one fully collateralized European covered-call
series. It locks WETH one-to-one with CALL, supports upward-rounded fractional
USDC strike payments during the exercise window, and permits one final writer
redemption after that window closes.

Run the contract checks:

```bash
cd contracts
forge fmt --check
forge build
forge test
```

These contracts are hackathon software and have not been audited. See the
[contract notes](contracts/README.md) for the current scope and boundaries.
The [baseline swap evidence](docs/BASELINE_SWAP_EVIDENCE.md) records the local
unmodified Aqua/SwapVM settlement proof.
The [custom-router settlement evidence](docs/CUSTOM_ROUTER_SETTLEMENT_EVIDENCE.md)
records the corresponding proof through the AquaVol opcode layer.
The [Base Sepolia Uniswap evidence](docs/BASE_SEPOLIA_UNISWAP_EVIDENCE.md)
documents the opt-in canonical-pool observation check and its limitations.
The [Base Sepolia deployment record](docs/BASE_SEPOLIA_DEPLOYMENT.md) tracks the
current public addresses, transactions, verification checks, and pending work.

## Uniswap integration

AquaVol creates a project-seeded WETH/avUSD pool through the official Base
Sepolia Uniswap V3 position manager and uses the pool exclusively as the
guarded spot input to option pricing. The adapter verifies factory identity,
token order, fee tier, a complete 30-minute observation window, latest
observation freshness, current and harmonic liquidity, spot/TWAP deviation,
and price bounds on every read.

Reviewers can verify the integration directly in:

- [`UniswapV3TwapOracle.sol`](contracts/src/oracles/uniswap/UniswapV3TwapOracle.sol) — guarded onchain TWAP reads
- [`UniswapV3OracleMath.sol`](contracts/src/oracles/uniswap/UniswapV3OracleMath.sol) — cumulative-tick and normalized quote calculation
- [`BootstrapUniswapV3Pool.s.sol`](contracts/script/BootstrapUniswapV3Pool.s.sol) — official factory and position-manager usage
- [`WriteTwapObservation.s.sol`](contracts/script/WriteTwapObservation.s.sol) — full-window check and SwapRouter02 observation write
- [`BaseSepoliaDeploymentRehearsal.t.sol`](contracts/test/fork/BaseSepoliaDeploymentRehearsal.t.sol) — end-to-end fork proof
- [`FEEDBACK.md`](FEEDBACK.md) — required Uniswap developer feedback

Public addresses, pool parameters, and transaction hashes are listed in the
[Base Sepolia deployment record](docs/BASE_SEPOLIA_DEPLOYMENT.md). The pool uses
the project-issued `avUSD` demo token and must not be interpreted as a canonical
USDC or production oracle market.

## Development approach

The project follows a spec-driven workflow. Specifications, prompts, planning
artifacts, provenance, and AI assistance will be committed alongside the
implementation so that the development process remains reviewable.

Current working documents:

- [Foundation specification](specs/00-foundation.md)
- [Product specification](specs/01-product.md)
- [Option lifecycle](specs/02-option-lifecycle.md)
- [Pricing model](specs/03-pricing-model.md)
- [Aqua and SwapVM integration](specs/04-aqua-swapvm-integration.md)
- [Security invariants](specs/05-security-invariants.md)
- [Demo acceptance](specs/06-demo-acceptance.md)
- [Custom SwapVM router](specs/07-custom-swapvm-router.md)
- [Uniswap V3 TWAP oracle](specs/08-uniswap-v3-twap-oracle.md)
- [Volatility registry and fair value](specs/09-volatility-and-fair-value.md)
- [Inventory-aware pricing](specs/10-inventory-aware-pricing.md)
- [Base Sepolia deployment](specs/11-base-sepolia-deployment.md)
- [Frontend strategy workspace](specs/12-frontend-strategy-workspace.md)
- [Engineering log](docs/ENGINEERING_LOG.md)
- [Dependency register](docs/DEPENDENCY_REGISTER.md)
- [Protocol provenance](docs/PROTOCOL_PROVENANCE.md)
- [Uniswap provenance](docs/UNISWAP_PROVENANCE.md)
- [PRBMath provenance](docs/PRB_MATH_PROVENANCE.md)
- [Base Sepolia deployment plan](docs/BASE_SEPOLIA_DEPLOYMENT_PLAN.md)
- [Base Sepolia fork rehearsal](docs/BASE_SEPOLIA_REHEARSAL.md)
- [Repository policy](docs/REPOSITORY_POLICY.md)

## Event references

- [ETHGlobal Tokyo 2026](https://ethglobal.com/events/tokyo2026)
- [ETHGlobal rules](https://ethglobal.com/events/tokyo2026/info/details#important-rules)
- [Event prize requirements](https://ethglobal.com/events/tokyo2026/prizes)
- [Aqua contracts](https://github.com/1inch/aqua)
- [SwapVM contracts](https://github.com/1inch/swap-vm)
- [Aqua TypeScript SDK](https://github.com/1inch/sdks/tree/master/typescript/aqua)

## Protocol attribution

Powered by Aqua — © Degensoft Ltd 2025.

Powered by SwapVM — © Degensoft Ltd 2025.

The pinned Aqua and SwapVM sources retain their upstream licenses and notices.
Any AquaVol component that modifies or extends SwapVM is published under
`LicenseRef-Degensoft-SwapVM-1.1`; independent AquaVol components keep their
own stated licenses. See [protocol provenance](docs/PROTOCOL_PROVENANCE.md).

## Testnet trust model

The planned Base Sepolia demo uses one dedicated, testnet-only operator wallet
as deployer, volatility updater, option writer, and Aqua maker. This consolidated
role can influence quotes and is a disclosed hackathon simplification, not a
production security model. A distinct browser-connected trader wallet provides
the independent counterparty for public transfer evidence. Neither identity
should hold mainnet assets, and no private key belongs in this repository.
