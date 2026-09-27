# Base Sepolia deployment rehearsal

## Scope

This record captures Prompt 0010 checkpoint 3. The complete deployment and
trade ran against a pinned Base Sepolia fork. No transaction was signed or
broadcast, and none of the AquaVol addresses below exist on the public network.

## Reproduction

From `contracts/`, run:

```bash
RUN_BASE_SEPOLIA_REHEARSAL=true \
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org \
forge test --match-contract BaseSepoliaDeploymentRehearsalTest -vv
```

The test pins Base Sepolia block `47,324,978`, verifies the official Uniswap V3
dependencies, funds only the local test operator with a Foundry cheatcode, and
advances time only inside the disposable fork.

## Rehearsed sequence

1. Validate chain ID `84532`, dependency bytecode, the 0.30% fee tier, and
   position-manager/router bindings.
2. Deploy capped `AquaVol Demo USD` (`avUSD`) with the local operator as minter.
3. Wrap fork-only ETH into canonical Base Sepolia WETH.
4. Create and initialize a WETH/avUSD pool through the official Uniswap V3
   position manager near 3,800 avUSD per WETH.
5. Increase observation capacity, add full-range liquidity, advance 30 minutes,
   and execute a small real V3 swap to write the mature observation.
6. Deploy the guarded TWAP oracle, volatility registry, `OptionSeries`, exact
   pinned Aqua source, and the modified AquaVol SwapVM router.
7. Set 64% implied volatility, lock 10 WETH, mint 10 CALL, approve Aqua, and
   ship 10 CALL plus 5,000 avUSD of virtual strategy balances.
8. Quote and settle an exact-output one-CALL purchase through Aqua from a
   distinct taker contract.
9. Requote the same immutable strategy and reconcile collateral, real token
   balances, and Aqua virtual balances.

## Deterministic result

Observed on 2026-09-26:

| Evidence | Fork result |
| --- | ---: |
| Base Sepolia fork block | `47,324,978` |
| Mature 30-minute TWAP | `3,799.749856 avUSD/WETH` |
| First one-CALL ask | `61.430458 avUSD` |
| Next one-CALL ask | `62.646903 avUSD` |
| Post-trade virtual CALL | `9 CALL` |
| Post-trade virtual quote | `5,061.430458 avUSD` |
| OptionSeries collateral | `10 WETH` |
| OptionSeries total supply | `10 CALL` |

The next ask increased while the strategy hash remained unchanged. The trader
received one CALL, the maker received the exact quoted avUSD, Aqua's virtual
balances changed by the same amounts, and all 10 WETH remained in
`OptionSeries`.

For reproducibility, the local-only addresses were:

| Component | Local fork address |
| --- | --- |
| DemoUSDC | `0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f` |
| WETH/DemoUSDC pool | `0x92c199Ceb017e38e6CFE71ECEE11c4967116F300` |
| TWAP oracle | `0x2e234DAe75C793f67A35089C9d99245E1C58470b` |
| OptionSeries | `0x1d1499e622D69689cdf9004d05Ec547d650Ff211` |
| Aqua | `0xF62849F9A0B5Bf2913b396098F7c7019b51A820a` |
| AquaVol SwapVM router | `0x5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9` |
| Strategy hash | `0x218260f23436960afbddb652c63864f179e70ced7f1f73444f02330036230645` |

## Limitations

- Every AquaVol address in this record is fork-local and has no public explorer
  transaction.
- Operator ETH, test-token minting, and time advancement are rehearsal-only.
- The liquidity position uses zero minimum amounts because execution is fully
  deterministic on a pinned fork; live scripts require reviewed slippage bounds.
- This proves deployment ordering and interface compatibility, not contract
  security, market quality, public source verification, or live RPC reliability.
