# Uniswap provenance

## Approved references

| Component | Revision | License record | Intended use |
| --- | --- | --- | --- |
| `Uniswap/v3-core` | `d0831dc6b8a318df3872b6d68f6de135c9f3ec29` | Repository BSL-1.1 record with a 2023-04-01 change to GPL-2.0-or-later; relevant interface/math file headers govern reuse | Pool interfaces and TickMath algorithm reference |
| `Uniswap/v3-periphery` | `0682387198a24c7cd63566a2c58398533860a5d1` | GPL-2.0-or-later | `OracleLibrary.consult()` and tick-quote algorithm reference |
| `Uniswap/sdks` | `60d7e07e9dd1c62a8b662effd1818c24c5e02ebc` | Reference repository license; no code import approved | Base Sepolia address registry only |

The revisions were resolved from the official repository HEADs on 2026-09-26.
No Uniswap package or repository is vendored. Prompt 0007 Checkpoint 2 added
only the attributed Solidity 0.8 adaptations listed below.

## Solidity compatibility finding

The pinned V3 periphery OracleLibrary declares a Solidity range below 0.8,
while AquaVol compiles with Solidity 0.8.30. Direct import was therefore not a
compatible implementation path. Checkpoint 2 adapted only the required pool
interfaces, cumulative-observation calculation, TickMath conversion, and
tick-quote logic under GPL-2.0-or-later. The isolated files contain exact source
revisions and modification notices; independent vectors exercise the math.

## Base Sepolia registry

The official Uniswap SDK registry currently identifies:

- V3 factory: `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`;
- position manager: `0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2`;
- swap router: `0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4`.

Read-only RPC checks on chain ID `84532` found deployed bytecode at the factory,
position manager, canonical WETH, and Circle test-USDC candidate addresses.
Factory resolution returned these WETH/test-USDC pools:

| Fee | Pool | Active liquidity | Observation cardinality | 30-minute `observe` |
| ---: | --- | ---: | ---: | --- |
| 0.05% | `0x94bfc0574FF48E92cE43d495376C477B1d0EEeC0` | `448098251397` | 180 | succeeded |
| 0.30% | `0x46880b404CD35c165EDdefF7421019F8dD25F4Ad` | `46364094458138` | 1801 | succeeded |
| 1.00% | `0x4664755562152EDDa3a3073850FB62835451926a` | `57734017049` | 1 | succeeded, but cardinality is unsuitable evidence by itself |

Observed ticks implied materially different testnet prices—approximately
`1,388`, `1,260`, and `1,506` USDC per WETH respectively—so existence and
historical readability do not establish economic quality. These pools are not
approved as the deterministic AquaVol demo authority by this record.

## Attribution and submission obligations

- Preserve every upstream SPDX identifier and notice in adapted files.
- Identify exact upstream files and revisions in source comments.
- Publish corresponding source for GPL-covered adaptations.
- Do not imply endorsement by Uniswap Labs or the Uniswap Foundation.
- Add `FEEDBACK.md`, submit the required developer feedback form, and link the
  final integration contract and relevant lines from the README before prize
  submission.

This provenance record is not legal advice.
