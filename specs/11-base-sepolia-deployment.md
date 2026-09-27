# Base Sepolia deployment specification

## Status

- Version: 0.2
- State: public market, Aqua position, and distinct-trader transaction
  completed; source verification and final manifest checks pending
- Updated: 2026-09-26
- Implementation authorization: Prompt 0010 checkpoint 4 in progress under
  explicit operator authorization; no repository commit or push is delegated

## Objective

Define a reproducible, review-gated Base Sepolia deployment that demonstrates
onchain token transfers through Aqua and inventory-aware execution through the
modified SwapVM router. This specification covers hackathon testnet operation;
it is not a production deployment policy.

## Network and authoritative dependencies

The deployment MUST fail unless `block.chainid == 84532`. Before simulation or
broadcast, a read-only preflight MUST confirm code at every configured external
dependency and validate contract identity through the interfaces AquaVol uses.

The official Uniswap V3 Base deployment registry was rechecked on 2026-09-26:

| Dependency | Base Sepolia address |
| --- | --- |
| Uniswap V3 factory | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` |
| Nonfungible position manager | `0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2` |
| SwapRouter02 | `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4` |
| Canonical WETH | `0x4200000000000000000000000000000000000006` |

Source: [official Uniswap V3 Base deployments](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-base-deployments).
These values are configuration inputs, not assumptions that bypass preflight.
They MUST be rechecked immediately before a live broadcast.

Official pinned Aqua source MUST be used without local modification. AquaVol's
modified SwapVM router MUST retain the recorded upstream revision, license,
change notices, and reproducible source. Deployed bytecode and constructor
inputs MUST be tied to the repository source commit in the manifest.

The custom pricing implementation MAY use an immutable external computation
engine when required to keep every deployed runtime below EIP-170. Such an
engine MUST be stateless, MUST NOT move or approve tokens, and MUST receive only
the strategy-bound arguments and current SwapVM query/register values. Its
address and runtime size MUST be recorded and verified alongside the router.

## Testnet identities and trust disclosure

The canonical public demo uses:

| Identity | Roles | Signing path |
| --- | --- | --- |
| Operator | deployer, volatility updater, writer, Aqua maker | ignored local environment or encrypted Foundry keystore |
| Trader | independent taker and option holder | browser wallet |

Combining operator roles is an explicit hackathon-only exception to the earlier
role-separation preference. The volatility updater can influence trading quotes
and the operator controls maker liquidity, so the UI and README MUST disclose
that centralization. Contract invariants still prevent the operator from
withdrawing OptionSeries collateral early or transferring trader-held tokens.

The two identities MUST be distinct during public trade evidence. Each MUST
hold its own Base Sepolia ETH gas buffer. Keys, seed phrases, signed raw
transactions, provider credentials, and populated environment files MUST NOT
appear in source, logs, manifests, screenshots, or committed shell history.

## Local configuration

The supported local variable names are:

```text
BASE_SEPOLIA_RPC_URL
OPERATOR_ADDRESS
MIN_OPERATOR_BALANCE_WEI (optional; defaults to the reviewed testnet floor)
PRIVATE_KEY (required only by a later broadcast checkpoint)
BASESCAN_API_KEY (optional until source verification)
```

The read-only preflight MUST use `OPERATOR_ADDRESS` and MUST NOT load
`PRIVATE_KEY`. The ignored `contracts/.env` MAY contain the testnet-only
operator key for later broadcast checkpoints. State-changing scripts MUST
reject an empty key, confirm its derived address matches `OPERATOR_ADDRESS`,
reject a chain-ID mismatch, and reject an operator balance below the reviewed
gas budget. Scripts MUST display only the public address, never the key. An
encrypted Foundry keystore remains preferred for repeated use.

The trader key is outside deployment configuration. The application requests
the trader signature through the connected browser wallet.

## Asset and market profile

- Underlying is canonical Base Sepolia WETH.
- Quote is a project-deployed six-decimal token named and symbolized so it
  cannot be mistaken for Circle USDC.
- The spot source is a project-seeded WETH/DemoUSDC Uniswap V3 pool created
  through the official factory.
- The initial price targets 3,800 DemoUSDC per WETH.
- Fee tier, initial square-root price, tick range, token amounts, recipient,
  and deadline MUST be shown in native units and human units before broadcast.
- Pool liquidity MUST be bounded to disposable testnet amounts.

Circle test-USDC pools MAY remain read-only comparison evidence. They MUST NOT
be described as the deterministic AquaVol market or used to conceal the
project-seeded nature of the authoritative test pool.

## Deployment graph

```text
official Uniswap V3 factory + position manager
                    |
          DemoUSDC + canonical WETH
                    |
          WETH/DemoUSDC V3 pool
                    |
       UniswapV3TwapOracle   VolatilityRegistry
                    \         /
                     OptionSeries
                          |
       official Aqua + AquaVolSwapVMRouter
                          |
              immutable pricing engine
                          |
             shipped Aqua strategy state
```

Constructor arguments and deployment order MUST be derived from a reviewed
configuration, not copied from console output. Option expiry MUST leave enough
time for deployment, the complete TWAP window, public trading, and the planned
demo. A deployment MUST abort rather than create an already expired or
operationally unusable series.

## Staged execution

1. **Preflight:** verify chain, signer address and balance, official addresses,
   code presence, source revision, compiler settings, and clean dependency
   state.
2. **Test assets:** deploy DemoUSDC, wrap the reviewed ETH amount, and verify
   balances without granting unlimited public mint authority.
3. **Spot market:** create or resolve the exact pool, validate token order,
   initialize once, expand observation capacity, and add reviewed liquidity.
4. **TWAP maturity:** wait the full configured window and produce enough
   observations; do not shorten safety parameters merely to avoid waiting.
5. **AquaVol graph:** deploy the oracle, registry, series, official Aqua,
   stateless pricing engine, and modified router in dependency order; verify
   immutable bindings and EIP-170 runtime sizes.
6. **Position:** update volatility, write collateralized CALL, approve exact
   token allowances, and ship the reviewed virtual balances.
7. **Trade evidence:** use the distinct trader wallet to quote and settle a
   bounded CALL purchase, then quote the same amount again.
8. **Verification:** reconcile balances/events, verify source where supported,
   and run the read-only manifest checker.

Every state-changing stage requires a successful simulation and explicit human
approval of its resolved values. Confirmation of one stage does not authorize
the next.

## Deployment manifest

The public manifest MUST contain no secrets and MUST record:

- schema version, network name, chain ID, explorer base URL, and RPC hostname
  without provider credentials;
- source commit, dirty-tree flag, compiler version, optimizer settings, and
  pinned Aqua, SwapVM, and PRBMath revisions;
- operator and trader public addresses with their disclosed roles;
- external dependency addresses and the source/date used to verify them;
- deployed contract addresses, constructor arguments, deployment transaction
  hashes, blocks, and source-verification status;
- pool address, fee, token order, initialization price, tick range, liquidity
  inputs, TWAP settings, and observation-maturity time;
- series terms, volatility value and freshness limit, inventory gamma, spread,
  shipped balances, and strategy hash;
- public trade transaction, before/after balances, events, next quote, and
  links to explorer evidence.

A partial deployment MUST be recorded as partial rather than overwritten or
represented as complete. Failed transactions MAY be recorded for diagnosis but
MUST be clearly labeled.

## Failure and recovery rules

- There is no destructive rollback for confirmed public transactions.
- A failed preflight or simulation causes no broadcast.
- An incorrectly initialized pool is abandoned and documented; it is not
  repaired by misleading labels or unsafe parameter changes.
- An incorrect immutable contract is redeployed and the superseded address is
  retained in the evidence record.
- A stale TWAP or volatility value stops quoting until the specified source is
  refreshed; no fallback spot or silent freshness extension is allowed.
- If public RPC or explorer infrastructure is unavailable, the demo uses the
  documented fork replay and clearly labels it as fallback evidence.

## Acceptance

Checkpoints 1–3 are complete: architecture, tooling, local validation, live
read-only preflight, and the complete pinned-fork rehearsal agree. The rehearsal
authorizes no broadcast, and all reported AquaVol addresses are local-only.
Checkpoint 4 requires separate review before any public transaction or claim of
public deployment.
