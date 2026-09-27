# Live wallet settlement specification

## Status

- Version: 0.1
- State: implemented and manually accepted on Base Sepolia
- Updated: 2026-09-27

## Scope

This specification covers browser-wallet execution for the one deployed
`avWETH-4000-C` series. It does not make simulated strikes, expiries, or PUTs
executable and does not add a general-purpose options factory.

## Network and identity

- Network: Base Sepolia, chain ID `84532` (`0x14a34`).
- Alice/operator: `0xA4A103c574a9bF22Bc49a7Ce3f089508300320d5`.
- Any other connected account is presented as a trader; the canonical public
  Bob account is `0xFC78e45702Ae93C1d062001184672c5679532251`.
- MetaMask signs every write. The application holds no signing material.
- Reads, simulations, and receipt polling use an explicit environment-selected
  RPC rather than an unauthenticated default provider.

## Live series

- Token: `avWETH-4000-C` at the deployed OptionSeries address.
- Underlying and collateral: canonical Base Sepolia WETH.
- Strike asset: six-decimal demo avUSD.
- Strike: 4,000 avUSD per whole CALL.
- Expiry: 2026-10-04 03:00:00 UTC.
- Exercise window: 24 hours.
- One whole CALL represents the right to exchange 4,000 avUSD for one WETH
  during the exercise window.

## Maker requirements

Writing `x` CALL requires exactly `x` WETH approval and collateral. Aqua's
`push` records inventory without transferring custody away from Alice, but the
push consumes its temporary allowance. Alice must subsequently approve Aqua for
the complete virtual CALL balance so settlement can pull inventory to traders.

Volatility refresh calls the immutable updater-bound registry with `0.64e18`.
TWAP refresh uses the official Base Sepolia Uniswap SwapRouter02, swaps exactly
1 avUSD into WETH through the deployed 0.30% pool, and requires at least
0.0002 WETH output. The limited 10 avUSD approval supports repeated demo
refreshes without granting an unlimited allowance.

## Trader requirements

Bob supplies an exact CALL output and maximum avUSD input. The frontend creates
a five-minute taker deadline, validates the canonical order hash, simulates the
router call, and asks MetaMask to submit only a successful simulation.

The packed taker header is:

```text
0x00250025002500250025002500250025002000200040
```

It contains exactly eight `0x0025` offsets, two `0x0020` offsets, and the
`0x0040` transfer-from-taker/Aqua-push flag. The 32-byte maximum input and
five-byte deadline follow the header.

## Safety and diagnostics

- `VolatilityStale` requires Alice to refresh IV.
- `LatestObservationTooOld(age, 120)` requires a new Uniswap observation and a
  trade within two minutes.
- `TakerTraitsExceedingMaxInputAmount` requires Bob to consciously increase and
  reapprove the payment ceiling; the UI must not silently remove this bound.
- `AquaBalanceInsufficientAfterTakerPush` indicates an invalid taker settlement
  mode or missing push and must not be treated as an oracle failure.
- Failed simulations do not submit transactions or mutate balances.

## Acceptance

- Alice's WETH wrap, approval, CALL write, Aqua push, and inventory allowance
  complete through MetaMask on Base Sepolia.
- Bob's avUSD approval and exact-output CALL purchase complete through MetaMask.
- Bob's avUSD decreases and CALL balance increases after confirmation.
- The immutable order hashes to
  `0x1a38d471dce4c9cc7a425010f584dd7ebaf5e0bbcdb42a67506dac1d91e465f5`.
- The frontend names the deployed spender and bounded amount for approvals.
- The frontend build succeeds without embedding a credential or private key.
