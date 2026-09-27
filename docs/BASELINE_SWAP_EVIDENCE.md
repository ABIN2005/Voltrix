# Unmodified Aqua/SwapVM baseline evidence

## Scope

Prompt 0005 Checkpoint 3 proves that AquaVol's CALL token can settle through
the pinned, unmodified Aqua and SwapVM execution path. This is a local Foundry
test, not Base Sepolia deployment evidence and not the final pricing strategy.

The program uses the upstream `XYCSwap` and `Salt` instructions. It contains no
AquaVol opcode or Black-Scholes calculation.

## Canonical local setup

| Item | Amount |
| --- | ---: |
| OptionSeries WETH collateral | 10 WETH |
| CALL written | 10 CALL |
| Aqua CALL virtual balance | 10 CALL |
| Aqua USDC virtual balance | 5,000 USDC |
| Trader request | Exact output of 1 CALL |
| Unmodified XYC quote | 555.555556 USDC |

The strategy is encoded once as `abi.encode(order)`. Aqua's `ship` result must
equal the official router's order hash before any swap is attempted.

## Required successful-swap evidence

For the unmodified constant-product baseline, the test first obtains the
authoritative router quote and then uses that input as the execution maximum.
It proves:

- quote and swap return identical CALL and USDC amounts;
- trader USDC decreases and trader CALL increases;
- writer USDC increases and writer CALL decreases by matching amounts;
- Aqua virtual USDC increases and virtual CALL decreases identically;
- the 10 WETH held by `OptionSeries` does not move during trading;
- live OptionSeries WETH remains equal to live CALL supply.

## Failure evidence

- changing the shipped order bytes changes its strategy hash and cannot access
  the funded virtual balances;
- requesting more CALL than the virtual balance reverts;
- both failures leave real balances, virtual balances, and collateral
  unchanged.

## Run

From `contracts/`:

```bash
forge test --offline --match-contract AquaSwapVMBaselineTest -vv
```

This checkpoint establishes protocol wiring only. It does not claim that the
constant-product price is an appropriate option premium.
