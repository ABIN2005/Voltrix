# Base Sepolia Uniswap V3 read-only evidence

## Purpose

This checkpoint verifies that AquaVol can discover and inspect an existing
WETH/test-USDC Uniswap V3 market on Base Sepolia without sending a transaction.
It is comparison evidence for the oracle integration, not the deterministic
project-seeded demo market and not a claim of production-grade price quality.

## Reproduce

Use a Base Sepolia archive-capable RPC endpoint and run from `contracts/`:

```bash
RUN_BASE_SEPOLIA_FORK=true \
BASE_SEPOLIA_RPC_URL="https://your-base-sepolia-rpc" \
forge test --match-path test/fork/BaseSepoliaUniswapV3.t.sol -vv
```

Without `RUN_BASE_SEPOLIA_FORK=true`, the fork test exits before reading an RPC.
The default local suite therefore remains network-independent.

## Verification boundary

The test:

- requires Base Sepolia chain ID `84532`;
- confirms bytecode and records code hashes for the official V3 factory,
  position manager, swap router, canonical WETH, and Circle test USDC;
- resolves the 0.30% WETH/test-USDC pool through `factory.getPool()`;
- verifies the resolved pool pair and fee;
- records current tick, active liquidity, observation index, cardinality, and
  latest-observation age;
- calls `observe([1800, 0])` and derives the official-style arithmetic mean tick
  and harmonic-mean liquidity;
- records the normalized 18-decimal USDC-per-WETH TWAP value.

All calls to network contracts are read-only. The test does not deploy or
broadcast, mutate a pool, add liquidity, or execute a swap. Fork selection and
test log emission occur only inside the local Foundry process.

## Registry inputs

| Component | Address |
| --- | --- |
| V3 factory | `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24` |
| V3 position manager | `0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2` |
| V3 swap router | `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4` |
| Canonical WETH | `0x4200000000000000000000000000000000000006` |
| Circle test USDC | `0x036CbD53842c5426634e7929541eC2318f3dCF7e` |

The pool address is intentionally absent from the inputs: it must be resolved
from the official factory during every verification run.

## Recorded check — 2026-09-26

The command above was executed against Base's public Sepolia RPC at block
`47324978` (`2026-09-26T10:24:04Z`) and passed with these observations:

| Field | Value |
| --- | ---: |
| Factory-resolved 0.30% pool | `0x46880b404CD35c165EDdefF7421019F8dD25F4Ad` |
| Current tick | `204970` |
| 30-minute arithmetic mean tick | `204958` |
| Current liquidity | `46364094458138` |
| 30-minute harmonic-mean liquidity | `46364094458138` |
| Observation index | `528` |
| Observation cardinality | `1801` |
| Latest observation timestamp | `1790417472` |
| Latest observation age | `772 seconds` |
| 30-minute USDC-per-WETH TWAP | `1256.701660000000000000` |

The complete 30-minute `observe([1800, 0])` call succeeded. However, the latest
observation was 772 seconds old, so an AquaVol oracle configured with a strict
120-second maximum age would correctly reject this pool at that block. Complete
history and recent activity are separate requirements.

The run also confirmed nonempty bytecode for every registry input and recorded
their code hashes in the Foundry output. Code hashes are intentionally not used
as timeless constants; future runs print the values again for comparison.

## Interpretation

Successful historical observation proves only that the pool exposes a complete
30-minute accumulator window at the selected block. Testnet liquidity can be
thin or concentrated, prices can diverge across fee tiers, and sequencer or RPC
conditions can affect availability. AquaVol therefore uses this canonical-token
market only as comparison evidence; the public demo plan calls for a clearly
labeled, project-seeded WETH/DemoUSDC market.
