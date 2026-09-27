# Custom SwapVM router specification

## Status

- Version: 0.1
- State: deterministic opcode, router, and local settlement verified
- Updated: 2026-09-26
- Implementation authorized: Prompt 0006 checkpoints 2 and 3 only

> Historical specification: the temporary `0xd0` implementation and its
> dedicated tests were retired after the production pricing path became
> `0xd1 → 0xd2`. This document remains as evidence of the staged development
> process; it no longer describes the active dispatcher.

### Deployment successor architecture

The active `0xd1 → 0xd2` implementation preserves the dispatcher and official
SwapVM settlement boundary proved by this historical checkpoint. For Base
Sepolia, computation-heavy pricing executes in an immutable, stateless
`AquaVolPricingEngine` because inlining Black-Scholes and inventory mathematics
produced a 32,620-byte router, above the 24,576-byte EIP-170 limit.

The deployed router copies only the current query and amount registers into a
read-only engine call, then copies the returned amount registers back into the
SwapVM context. The engine cannot access Aqua settlement authority, transfer
tokens, approve spenders, or persist pricing state. Aqua and the official
SwapVM flow remain solely responsible for token movement and virtual-balance
accounting. The engine address is immutable and part of the router's public
deployment evidence.

## Objective

Introduce the smallest reviewable SwapVM extension that proves AquaVol can run
a custom instruction inside the official Aqua settlement path. This phase uses
a deterministic constant price so router mechanics can be verified before
oracle, fixed-point, Black-Scholes, or inventory risk is introduced.

## Source and license boundary

The pinned `contracts/lib/aqua` and `contracts/lib/swap-vm` submodules MUST stay
unchanged. AquaVol extension files live outside both submodules and MUST:

- use `LicenseRef-Degensoft-SwapVM-1.1` where they modify or extend SwapVM;
- name the upstream revision and mark the AquaVol change date;
- preserve required notices and attribution;
- remain reproducible from committed source and tests.

This phase does not modify Aqua.

## Opcode allocation

| Value | Canonical name | Arguments | Output responsibility |
| --- | --- | --- | --- |
| `0xd0` | `AQUAVOL_CONSTANT_PRICE` | Fixed premium in token-native units | Set the required swap amount for the supported direction and mode |
| `0xd1` | `OPTION_FAIR_VALUE` | Not defined in this phase | Reserved; MUST revert as unknown until implemented |
| `0xd2` | `OPTION_INVENTORY_SKEW` | Not defined in this phase | Reserved; MUST revert as unknown until implemented |

The values are selected from the pinned upstream unallocated bank. Values
`0xf0–0xff` MUST never be allocated. A single canonical AquaVol constants
library MUST define these values; tests MUST detect mapping drift.

`AQUAVOL_CONSTANT_PRICE` is temporary integration scaffolding, not an option
valuation model. It MUST be removed or disabled before the final deployment.

## Router architecture

The implementation SHOULD contain three focused layers:

1. an AquaVol opcode constants and instruction-encoding layer;
2. an `AquaVolOpcodes` dispatcher that handles known AquaVol values and calls
   the pinned upstream dispatcher for every other value;
3. an `AquaVolSwapVMRouter` that preserves the official router's Aqua and WETH
   bindings, simulation behavior, VM execution, and settlement interface.

The extension MUST NOT edit the upstream `Opcode` enum merely to assign names
to placeholder values. The local instruction builder MAY emit the raw two-byte
header used by the pinned VM: one opcode byte followed by one argument-length
byte, then the arguments. It MUST reject arguments that cannot fit that header.

## Execution constraints

The custom opcode MUST:

- be deterministic for identical order bytes, taker data, and chain state;
- mutate only the VM swap registers needed to describe settlement amounts;
- perform no token transfer, approval, Aqua balance mutation, or external call;
- use token-native integer units and document rounding behavior;
- reject malformed argument length, zero premium, unsupported direction, and
  unsupported exact-input/exact-output mode;
- preserve upstream deadline, token, threshold, and liquidity validation.

No custom persistent storage is authorized. Constructor state inherited from
the official router is permitted.

## Checkpoint 2 acceptance

Unit tests MUST prove:

- the builder emits the exact expected instruction bytes;
- `0xd0` dispatches to the deterministic handler;
- an unchanged upstream instruction still dispatches through `super`;
- `0xd1`, `0xd2`, reserved-bank, and unknown values revert;
- malformed and unsupported constant-price instructions revert;
- no custom handler transfers tokens directly.

## Checkpoint 3 acceptance

The integration suite MUST reuse the canonical CALL/USDC scenario and prove:

- quote and swap agree for unchanged state and inputs;
- the fixed premium, rather than the prior constant-product curve, determines
  the expected USDC amount;
- maker, trader, and Aqua real/virtual balance deltas reconcile;
- OptionSeries collateral remains unchanged;
- the same router still executes one supported upstream program;
- thresholds, altered order bytes, and insufficient liquidity revert without
  partial settlement.

The checkpoint is local-only. It does not authorize fair-value math, inventory
skew, oracles, TypeScript packages, UI work, or Base Sepolia deployment.
