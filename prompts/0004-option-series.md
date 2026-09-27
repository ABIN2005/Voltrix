# Prompt 0004: Implement the collateralized option series

- Date: 2026-09-26
- Input state: approved AquaVol MVP specifications and verified Python vectors
- Authorized scope: isolated Solidity option lifecycle and Foundry tests

## Task

Implement the single-writer `OptionSeries` defined by the lifecycle and security
specifications. This phase must:

- lock standard 18-decimal WETH one-to-one with newly minted CALL units;
- expose CALL as a transferable 18-decimal ERC-20 token;
- accept writing only from the immutable writer before expiry;
- accept exercise only during the 24-hour exercise window;
- round fractional strike payments upward when converting WAD strike values to
  6-decimal USDC units;
- burn exercised CALL, collect strike USDC, and deliver WETH atomically;
- let the writer redeem remaining WETH and accumulated USDC once, after the
  exercise window;
- reject incomplete incoming token transfers and reentrant lifecycle calls;
- contain no oracle, pricing, Aqua, SwapVM, frontend, or deployment logic.

Use a self-contained Foundry project without runtime package dependencies.
Provide unit, fuzz, and stateful invariant coverage for authorization, timing,
rounding, collateral solvency, exercise, and final redemption.

## Expected output

```text
contracts/
  foundry.toml
  src/
    interfaces/IOptionSeries.sol
    libraries/FullMath.sol
    options/OptionSeries.sol
    mocks/MockERC20.sol
  test/
    OptionSeries.t.sol
    OptionSeriesInvariant.t.sol
```

## Exit gate

From `contracts/`, `forge fmt --check`, `forge build`, and `forge test` must
pass. The implementation must preserve one unit of live WETH collateral for
every exercisable CALL unit before final redemption.

## Repository boundary

Do not stage files, commit changes, or push to a remote repository.
