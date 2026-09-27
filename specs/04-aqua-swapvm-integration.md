# Aqua and SwapVM integration specification

## Status

- Version: 0.7
- State: custom-router settlement, fair value, inventory skew, and dynamic Aqua
  repricing implemented and tested
- Implementation authorized: Prompt 0010 may deploy the tested integration
  through its review-gated checkpoints

## Integration objective

The integration MUST prove that current Aqua liquidity state participates in
SwapVM pricing and that the resulting accepted quote settles real CALL and USDC
transfers through the official Aqua/SwapVM execution model.

## Dependency provenance

Before code is imported or installed, the project MUST record for Aqua,
SwapVM, and their SDKs:

- upstream repository;
- exact commit or release;
- license and notice obligations;
- imported paths;
- local modifications;
- deployment addresses and verification links.

The project MUST first reproduce one unmodified Aqua-backed swap locally. A
custom opcode is not considered integrated until that baseline passes.

## Deployment topology

The intended Base Sepolia topology is:

```text
OptionSeries
UniswapV3TwapOracle
VolatilityRegistry
Official Aqua contract or exact-source redeployment
AquaVol SwapVM router derived from the pinned official implementation
Mock or faucet WETH and USDC appropriate for the test network
```

If official compatible deployments are unavailable, exact-source redeployment
is permitted only after the upstream version and deployment configuration are
recorded. Any modification MUST be isolated and documented.

## Strategy identity

The maker MUST build one canonical encoded Aqua-backed SwapVM order. The exact
same bytes MUST be used to:

- calculate the strategy hash;
- call Aqua `ship()`;
- request SwapVM quotes;
- execute SwapVM swaps;
- display strategy identity in the UI.

Independent encoders for shipping and execution are forbidden.

## Strategy parameters

The immutable strategy program MUST bind at least:

- maker;
- CALL token;
- WETH underlying;
- USDC quote token;
- strike;
- expiry;
- Uniswap spot-oracle address, TWAP window, minimum harmonic-mean liquidity,
  and maximum latest-observation age;
- volatility-registry address and maximum age;
- initial CALL inventory `Q0`;
- inventory gamma;
- half-spread;
- direction and mode restrictions;
- unique salt where required.

Changing any bound parameter requires docking the old strategy and shipping a
new strategy. Updating data inside the bound oracle contracts follows their
separately disclosed trust model.

## Custom instruction set

The canonical AquaVol opcode mapping is:

| Opcode | Name | Phase |
| --- | --- | --- |
| `0xd0` | `AQUAVOL_CONSTANT_PRICE` | Temporary deterministic integration proof |
| `0xd1` | `OPTION_FAIR_VALUE` | Reserved for later pricing implementation |
| `0xd2` | `OPTION_INVENTORY_SKEW` | Reserved for later inventory implementation |

The pinned upstream version declares `0xd0–0xef` unallocated and `0xf0–0xff`
reserved. AquaVol MUST NOT allocate any value in the reserved bank. Solidity
and TypeScript opcode tables MUST be generated from or tested against one
canonical mapping.

The router MUST delegate all unaffected behavior to the pinned official
implementation. Custom instructions MUST calculate register values only and
MUST NOT transfer tokens.

## Program order

The initial program is conceptually:

```text
validate deadline and supported direction
          ->
OPTION_FAIR_VALUE
          ->
OPTION_INVENTORY_SKEW
          ->
standard balance and threshold validation
          ->
settlement
```

Instruction ordering is security-critical. Tests MUST show that unsupported
orders or reordered programs do not bypass validation.

## Supported execution modes

### Buy CALL

- Taker supplies USDC.
- Taker requests exact CALL output.
- Current CALL inventory is the relevant maker output balance.
- SwapVM computes the maximum required USDC amount from fair value, average
  inventory exposure, and spread.
- The taker supplies `maxAmountIn` and a deadline.

### Sell CALL back

- Taker supplies exact CALL input.
- Maker returns USDC.
- Current CALL inventory is the relevant maker input balance.
- SwapVM rejects a trade that would raise CALL inventory above `Q0`.
- The taker supplies `minAmountOut` and a deadline.

All other direction/mode combinations MUST revert in the MVP.

## Aqua lifecycle

The maker flow is:

1. write CALL tokens against WETH collateral;
2. approve Aqua for CALL and USDC;
3. encode the immutable order and program;
4. ship virtual CALL and USDC amounts to the modified router application;
5. verify the emitted Aqua strategy event and derived strategy hash.

The maker MAY dock the strategy while the series remains active. Docking MUST
not affect OptionSeries collateral or outstanding CALL rights.

## Settlement evidence

For a successful buy, the transaction MUST prove:

```text
trader USDC decreases
maker USDC increases
maker CALL decreases
trader CALL increases
Aqua virtual USDC increases
Aqua virtual CALL decreases
```

For a successful sell-back, the inverse changes MUST occur within configured
inventory and balance limits.

The project MUST capture transaction hashes, emitted events, and pre/post token
and Aqua balances.

## Quote consistency

For unchanged block state and inputs:

```text
quote(order, taker data) == swap(order, taker data)
```

The UI MAY preview calculations independently but MUST treat the router quote
as authoritative. Execution MUST include taker thresholds and a short deadline.

## TypeScript responsibilities

A shared TypeScript package SHOULD provide:

- canonical strategy types;
- custom opcode mapping;
- strategy and taker-data encoding;
- event parsing;
- Base Sepolia deployment manifest types;
- conversion between display decimals and token-native integers.

The React application and optional Node service MUST consume this shared
package. Duplicated wire formats are forbidden.

## Backend boundary

The canonical MVP SHOULD operate without a required backend. A Node service MAY
be added for indexing or convenience only after the browser can:

- connect a wallet;
- read the deployed contracts;
- obtain an authoritative quote;
- submit and confirm a transaction;
- display resulting state.

## Integration acceptance

Tests or scripts MUST demonstrate in dependency order:

1. unmodified Aqua-backed reference swap;
2. modified router with a trivial deterministic custom opcode;
3. CALL/USDC transfer through Aqua at a fixed premium;
4. Black-Scholes fair-value instruction;
5. inventory-skew instruction using live Aqua balances;
6. quote, swap, post-swap repricing, sell-back, and exercise;
7. verified Base Sepolia deployment and public transfer transaction.

## Approved baseline pins

- Aqua: `ef24220ed9647555727b06867bf509cd6959d84b`
- SwapVM: `feb16411738331f7d05ae71d4a664154068018fc`
- Aqua SDK reference: `3dbd4fd17fdc9fb814b8d55b3efcf4a39eddb32c`

Prompt 0005 authorized an unmodified local Aqua/SwapVM swap in three reviewed
checkpoints. Prompt 0006 authorizes an isolated modified router, the temporary
`AQUAVOL_CONSTANT_PRICE` opcode, and compatibility tests. Fair-value,
inventory-skew, oracle, TypeScript, and public deployment code remain
unauthorized.

The Checkpoint 3 local test demonstrates a CALL/USDC exact-output swap,
quote/execution consistency, real and virtual balance reconciliation,
unchanged OptionSeries collateral, altered-strategy rejection, and insufficient
liquidity rejection using the pinned unmodified contracts.

## Unresolved after baseline approval

- Exact Base Sepolia Aqua deployment approach.
- Test-token addresses and acquisition method.
- Whether the modified router needs any custom storage beyond inherited state;
  the preferred answer is no.
