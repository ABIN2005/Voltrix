# AquaVol custom-router settlement evidence

> Historical evidence: this document records the temporary `0xd0` integration
> checkpoint. The implementation and dedicated suite were later removed after
> `0xd1 → 0xd2` inventory-aware settlement passed. The executable historical
> suite remains available through Git history.

## Scope

Prompt 0006 Checkpoint 3 proves that the AquaVol-modified SwapVM router can
calculate a deterministic CALL premium and settle the resulting real token
transfers through the pinned Aqua contract. It also proves that the extension
preserves an unaffected upstream instruction path.

This is local Foundry evidence. The fixed premium is integration scaffolding,
not onchain Black-Scholes pricing, and this document is not Base Sepolia
deployment evidence.

## Canonical custom strategy

| Item | Amount |
| --- | ---: |
| OptionSeries WETH collateral | 10 WETH |
| CALL written | 10 CALL |
| Aqua CALL virtual balance | 10 CALL |
| Aqua USDC virtual balance | 5,000 USDC |
| Trader request | Exact output of 1 CALL |
| `AQUAVOL_CONSTANT_PRICE` premium | 61.505937 USDC |

The program contains the ABI-encoded CALL address, USDC address, and premium,
followed by an upstream salt instruction. Its exact order bytes determine both
the router hash and the Aqua strategy identity.

## Successful settlement evidence

The test obtains an authoritative quote from the router and executes with that
amount as the maximum USDC input. It proves:

- the custom opcode returns exactly `61.505937` USDC for one CALL;
- the result differs from the prior constant-product baseline;
- quote and swap return the same input and output amounts;
- trader USDC decreases and trader CALL increases by those amounts;
- writer USDC increases and writer CALL decreases identically;
- Aqua virtual USDC increases and virtual CALL decreases identically;
- OptionSeries WETH does not move and continues to equal live CALL supply.

## Upstream compatibility evidence

A second strategy uses the pinned upstream `XYCSwap` and `Salt` instructions
with the same balances. The AquaVol router quotes and settles the expected
`555.555556` USDC input for one CALL, demonstrating that non-AquaVol opcodes
still delegate to the official dispatcher.

## Atomic failure evidence

The integration suite separately rejects:

- a `61.505936` USDC maximum input, one native USDC unit below the quote;
- altered order bytes that do not match the shipped strategy;
- a request one wei above the 10 CALL virtual balance.

Every failure preserves trader and writer token balances, Aqua virtual
balances, WETH collateral, and CALL supply.

## Run

At the historical checkpoint, from `contracts/`:

```bash
forge test --offline --match-contract AquaVolSwapVMSettlementTest -vv
```

Prompt 0006 is complete when this suite, the custom-router unit suite, existing
AquaVol tests, Python reference tests, and pinned upstream suites all pass.
