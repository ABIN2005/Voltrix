# Engineering log

This file records decisions that constrain later specifications or
implementation. Entries are append-only; superseded decisions remain visible
and point to their replacement.

## E-001 — Separate reference math from settlement

- Date: 2026-09-26
- State: accepted

Python is the independent mathematical reference environment. It may generate
vectors and simulations but is not part of transaction authorization or live
settlement. Solidity remains authoritative for enforceable outcomes.

Reason: a reference implementation is most valuable when it is independent of
the implementation it checks.

## E-002 — Use Base Sepolia for public evidence

- Date: 2026-09-26
- State: accepted with deployment work pending

The canonical public demonstration will target Base Sepolia. Official contract
deployment availability must be verified before implementation. If compatible
official deployments are unavailable, exact upstream versions and any local
modifications must be recorded before redeployment.

## E-003 — Do not scaffold application code during discovery

- Date: 2026-09-26
- State: accepted

React, service, Python, and Foundry scaffolds are deferred until the position
lifecycle and settlement boundary are specified.

Reason: generated structure would imply interfaces and dependencies that have
not yet been justified by product behavior.

## E-004 — Keep the canonical demo dependency-light

- Date: 2026-09-26
- State: proposed

Prefer wallet, public RPC, deployed contracts, and browser-readable chain state
for the canonical path. A backend or indexer becomes mandatory only when the
approved position cannot be demonstrated reliably without it.

## E-005 — Freeze the canonical covered-call MVP

- Date: 2026-09-26
- State: accepted

The canonical market uses one writer, one WETH/USDC European call series, 10
WETH collateral, a 4,000 USDC strike, seven initial days to expiry, a 24-hour
exercise window, 64% implied volatility, 20% inventory gamma, and a 1%
half-spread. Exact-output buys and exact-input sell-backs are both in scope.

CALL tokens remain transferable after expiry, but Aqua trading stops at expiry.
Public swap evidence targets Base Sepolia; deterministic exercise uses a labeled
local-fork replay.

## E-006 — Authorize the independent math phase

- Date: 2026-09-26
- State: accepted

The first implementation artifact is a standard-library Python reference and
versioned test vectors. It is independent of the live execution path. Solidity,
Aqua, SwapVM, TypeScript, and UI implementation remain unauthorized until the
reference results are reviewed.

## E-007 — Isolate the collateral contract phase

- Date: 2026-09-26
- State: accepted

Prompt 0004 authorizes `OptionSeries` and its Foundry tests without authorizing
Aqua, SwapVM, oracle, deployment, or frontend work. The series uses no runtime
package dependency. It accepts only exact incoming WETH and USDC transfers,
uses upward rounding for fractional strike settlement, and protects every
lifecycle mutation with a reentrancy guard.

Reason: proving collateral solvency and exercise behavior independently keeps
later trading and pricing failures outside the option holder's settlement
rights.

## E-008 — Prove the unmodified protocol path first

- Date: 2026-09-26
- State: accepted

The Aqua and SwapVM integration is split into three human-reviewed commits:
provenance and specification, a pinned upstream harness, and an unmodified
end-to-end swap test. Custom opcodes are not authorized until that baseline
reconciles maker, trader, and Aqua virtual balances.

Reason: this separates upstream integration failures from errors introduced by
AquaVol's later mathematical instructions and produces meaningful Git history
without fragmenting the work into cosmetic commits.

## E-009 — Accept the unmodified local settlement baseline

- Date: 2026-09-26
- State: accepted

The pinned official Aqua and SwapVM contracts settle an exact-output CALL buy
against 10 CALL and 5,000 USDC of virtual liquidity. The authoritative quote,
real maker/trader transfers, and Aqua virtual-balance changes reconcile while
OptionSeries retains all WETH collateral. Altered order bytes and insufficient
CALL liquidity revert without partial settlement.

This accepts protocol wiring only. The upstream constant-product instruction
is not the AquaVol option-pricing model and must be replaced by separately
authorized custom pricing instructions.

## E-010 — Isolate custom opcodes from the pinned submodules

- Date: 2026-09-26
- State: accepted

AquaVol will leave both upstream Git submodules unchanged. A new derivative
router and opcode dispatcher will intercept AquaVol instructions and delegate
all other instructions to the pinned official implementation. The extension
will add no custom storage and custom opcodes will only calculate swap-register
values; Aqua remains responsible for token settlement.

At pinned SwapVM revision `feb16411738331f7d05ae71d4a664154068018fc`, the
`0xd0–0xef` bank is unallocated and `0xf0–0xff` is permanently reserved.
AquaVol allocates `0xd0` to a temporary deterministic constant-price proof and
reserves `0xd1` and `0xd2` for fair value and inventory skew. The temporary
opcode must not be presented as production pricing and must be removed or
disabled before the final deployment.

The derivative router boundary follows `LicenseRef-Degensoft-SwapVM-1.1`, with
marked changes, source availability, reproducible instructions, preserved
notices, and the required README/UI attribution.

## E-011 — Accept the deterministic custom-router foundation

- Date: 2026-09-26
- State: accepted with integration pending

The AquaVol router, dispatcher, raw instruction builder, and temporary `0xd0`
constant-price instruction compile against the pinned protocol revisions. Unit
tests prove canonical encoding, ceiling rounding, liquidity and mode guards,
upstream opcode delegation, reserved-value rejection, unchanged token balances,
and inherited Aqua/WETH bindings.

The instruction supports only exact-output quote-to-CALL calculation and has no
external calls or persistent storage. Acceptance of this unit layer does not
claim modified-router settlement; Prompt 0006 Checkpoint 3 must demonstrate
that separately through Aqua.

## E-012 — Accept modified-router Aqua settlement

- Date: 2026-09-26
- State: accepted as local integration evidence

The AquaVol router quotes and settles an exact-output one-CALL purchase for the
configured `61.505937` USDC proof premium. Real maker/trader transfers and Aqua
virtual balances reconcile, while the OptionSeries WETH collateral remains
untouched and fully backs live CALL supply.

The modified router also settles the pinned upstream constant-product program
at its independently expected `555.555556` USDC result. Maximum-input failure,
altered order bytes, and insufficient CALL liquidity all revert without partial
state changes. This accepts the custom dispatch and settlement path only; the
constant-price instruction remains temporary and is not production valuation.

## E-013 — Use Uniswap V3 TWAP for spot input

- Date: 2026-09-26
- State: accepted for Prompt 0007

AquaVol will replace the administrator-updated spot input with a strategy-bound
Uniswap V3 time-weighted average. Implied volatility remains a separately
bounded administrator input because a spot TWAP is not implied volatility.

The generic adapter will validate the official factory, exact pool and pair,
fee tier, token order, decimal normalization, full observation window, latest
observation age, harmonic-mean liquidity, and an optional deviation circuit
breaker. It will fail closed and will not fall back to `slot0()` pricing.

Read-only Base Sepolia checks found canonical WETH/Circle test-USDC pools at all
three standard fee tiers. Their observed prices differed materially from each
other and from the canonical AquaVol scenario. The public deterministic demo
will therefore use canonical Base Sepolia WETH with clearly labeled DemoUSDC in
a project-seeded pool created by the official V3 factory. The existing 0.30%
canonical pool remains a comparison feed, not the authoritative demo input.

## E-014 — Separate volatility administration from fair-value math

- Date: 2026-09-26
- State: proposed for Prompt 0008 review

Implied volatility will remain a separately timestamped administrator input,
keyed by immutable `OptionSeries` address and bounded to 0.01%–500% annualized.
The updater cannot custody collateral or maker liquidity. Missing, stale,
future-dated, or out-of-range data stops trading rather than falling back.

Solidity fair value will use PRBMath `v4.2.0` at commit
`29a3c06c709496a8f9775dea115935befc5158a7`, a bounded Abramowitz and Stegun
normal-CDF approximation, and the existing Python vectors as the independent
reference. Opcode `0xd1` reads series terms, guarded TWAP evidence, and the
volatility record through static calls to addresses bound in strategy bytes.
Inventory exposure and spread remain isolated for a later prompt.

## E-015 — Compose fair value with live Aqua inventory

- Date: 2026-09-26
- State: proposed for Prompt 0009 review

The inventory instruction will consume the total USDC-native fair-value amount
already written by opcode `0xd1`, then apply average exposure, inventory gamma,
and half-spread using the CALL balance already loaded from Aqua. It will not
recompute Black-Scholes or accept a taker-provided price.

Opcode `0xd2` binds the CALL and USDC pair, guarded oracle, initial CALL
inventory, gamma, and spread in 192 bytes of immutable strategy arguments. The
oracle is read again only to cap the final adjusted premium at spot. Buy
adjustments round upward and sell-back adjustments round downward at both the
inventory and spread stages.

The canonical builder emits `0xd1` followed by `0xd2`. Missing-register guards
make reversed or missing instructions fail closed, while Aqua's complete-order
strategy hash isolates any altered program from canonical liquidity. The
temporary `0xd0` path remains only until inventory-aware settlement and dynamic
repricing pass their own review checkpoint.

## E-016 — Retire deterministic pricing scaffolding

- Date: 2026-09-26
- State: accepted after Prompt 0009 dynamic-settlement verification

The canonical AquaVol strategy now composes `0xd1` fair value with `0xd2`
inventory skew and settles exact-output buys and exact-input sell-backs through
the pinned Aqua and SwapVM contracts. Unchanged strategy bytes reprice from live
Aqua CALL balances, block and sequential fills remain inside the declared
rounding budget, and real and virtual balance changes reconcile.

Opcode `0xd0`, its constant-price implementation, and its dedicated settlement
tests are retired. Historical specifications, evidence, and commits remain
available to explain the staged integration path, while the active dispatcher
exposes only `0xd1` and `0xd2` from AquaVol's opcode bank.

## E-017 — Use a disclosed two-wallet Base Sepolia operating model

- Date: 2026-09-26
- State: accepted for Prompt 0010 architecture review

The public hackathon deployment uses one disposable, testnet-only operator as
deployer, volatility updater, option writer, and Aqua maker, with a distinct
browser-connected trader. This consolidation reduces deployment coordination
while preserving an independent counterparty for visible token-transfer
evidence. It supersedes the earlier absolute demo-key separation requirement
only for the Base Sepolia hackathon profile.

The operator's ability to change implied volatility and control maker liquidity
must be disclosed in the README, UI, and deployment manifest. Contract-enforced
collateral isolation, oracle freshness, pricing bounds, Aqua accounting, and
trader-token authorization remain unchanged. Production use would require
separated roles, stronger key management, governance, and an audit.

## E-018 — Accept the pinned Base Sepolia deployment rehearsal

- Date: 2026-09-26
- State: accepted as local-fork deployment evidence

At pinned Base Sepolia block `47,324,978`, the checkpoint-3 rehearsal validated
the official Uniswap V3 dependencies, created and matured a project WETH/avUSD
pool, deployed exact pinned Aqua plus the complete AquaVol graph, wrote and
shipped the covered-call position, and settled a distinct-taker CALL purchase.

The mature TWAP was `3,799.749856` avUSD/WETH. One CALL settled for
`61.430458` avUSD, leaving 9 virtual CALL and producing a higher unchanged-
strategy next ask of `62.646903` avUSD. Ten WETH of collateral remained against
10 CALL total supply. All AquaVol addresses, funding, time advancement, and
transactions in this evidence are local to the fork and are not public
deployment claims.

## E-019 — Externalize custom opcode computation for EIP-170

- Date: 2026-09-26
- State: accepted and deployed on Base Sepolia

The initially simulated custom router compiled to 32,620 runtime bytes, above
the 24,576-byte EIP-170 limit, so it was not broadcast. Lower optimizer runs
still produced 31,791 bytes and did not solve the deployment constraint.

The final architecture keeps the official SwapVM-derived router and active
`0xd1`/`0xd2` dispatcher, but binds it immutably to a stateless read-only
`AquaVolPricingEngine`. The router forwards only the strategy arguments and
current SwapVM registers; the engine returns updated amount registers and
cannot settle or custody tokens. This produces a 22,503-byte router and an
11,201-byte engine. The complete 135-test suite passed before broadcast, and
onchain reads verified both runtime sizes and the immutable engine binding.

## E-020 — Accept the Base Sepolia distinct-trader settlement

- Date: 2026-09-26
- State: accepted as public onchain evidence

The disposable trader `0xFC78e45702Ae93C1d062001184672c5679532251`
bought exactly 0.01 CALL through the deployed modified SwapVM router and exact-
source Aqua. The taker encoded a 1 avUSD maximum input and paid 0.779818 avUSD.
The trader's CALL balance increased by 0.01, Aqua virtual CALL decreased from
0.10 to 0.09, and virtual avUSD increased from 50 to 50.779818. OptionSeries
retained 0.10 WETH against unchanged 0.10 CALL total supply. The public swap
transaction is
`0xb49b7574aa15a92cb96fb6b804279ca321488dcd1b43a8c6bb780a9dd1cf7379`.
After a fresh public observation, the read-only verifier reported a
3,842.159899 avUSD/WETH TWAP and a higher next 0.01 CALL ask of 0.815649 avUSD
without changing the strategy hash.

## E-021 — Accept browser-wallet Aqua settlement

- Date: 2026-09-27
- State: accepted through manual Base Sepolia execution

The React workspace now separates the immutable operator from connected trader
accounts and exposes real MetaMask transactions for the deployed CALL only.
Alice wrapped WETH, approved collateral, wrote additional CALL, pushed inventory
through Aqua, restored the settlement allowance, and refreshed bounded pricing
inputs. Bob approved avUSD and completed another exact-output CALL purchase
through the deployed modified SwapVM router.

Manual debugging confirmed three independent fail-closed boundaries. A stale
volatility record produced `VolatilityStale`; an observation older than the
immutable 120-second maximum produced `LatestObservationTooOld`; and a live ask
above Bob's one-avUSD threshold produced `TakerTraitsExceedingMaxInputAmount`.
The UI retains these guards and provides operator maintenance actions instead
of bypassing them.

The first browser taker encoder accidentally emitted nine `0x0025` offsets,
making its header 24 rather than 22 bytes and shifting the `0x0040` flag out of
the parsed traits. This produced `AquaBalanceInsufficientAfterTakerPush`. The
accepted encoder now matches `TakerTraitsLib.build`: eight `0x0025` offsets,
two `0x0020` offsets, and the `0x0040` flag, followed by the threshold and
deadline. A successful Bob settlement after this correction accepted the live
wallet checkpoint. Its transaction hash remains to be copied from the frontend
confirmation link into the public evidence record.
