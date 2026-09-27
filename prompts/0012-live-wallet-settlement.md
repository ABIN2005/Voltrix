# Prompt 0012: Connect live maker and trader settlement

- Date: 2026-09-27
- Input state: the strategy workspace and public Base Sepolia deployment are
  complete; live wallet execution remains to be demonstrated through the UI
- Authorized scope: browser-wallet reads and writes against the single deployed
  CALL, operational oracle refresh actions, and explicit transaction diagnostics

## Objective

Turn the read-only strategy workspace into a genuine two-wallet demonstration.
Alice must be able to write and expose additional covered CALL inventory through
the deployed OptionSeries and Aqua contracts. Bob must be able to purchase the
single live CALL through the deployed modified SwapVM router with an exact-output
amount and bounded avUSD payment.

All signing remains inside MetaMask. The frontend must never receive a private
key, mint an undeployed simulated instrument, or label a simulated strike, PUT,
or expiry as executable.

## Alice maker flow

Expose explicit, separately signed actions for:

1. wrapping ETH into canonical Base Sepolia WETH;
2. approving exact WETH collateral to OptionSeries;
3. writing the covered CALL;
4. optionally adding the CALL ERC-20 to MetaMask;
5. approving and pushing exact CALL inventory into Aqua;
6. restoring Aqua's allowance for the complete virtual CALL inventory;
7. refreshing the bounded 64% volatility record;
8. approving a limited avUSD budget to the official Uniswap V3 router; and
9. creating a fresh pool observation before the guarded live trade.

The UI must identify the recipient contract and amount for every approval.

## Bob trader flow

For any connected wallet other than Alice, expose only the deployed WETH 4,000
CALL. Bob chooses an exact CALL output and a maximum six-decimal avUSD input,
approves the modified SwapVM router, executes the immutable Aqua order, and may
add the received CALL token to MetaMask.

The taker data must be rebuilt with a fresh five-minute deadline. Its header is
exactly 22 bytes: ten `uint16` slice offsets followed by `uint16(0x0040)`, which
selects the SwapVM transfer-from-taker plus Aqua-push settlement path. For the
canonical threshold-and-deadline payload the offsets are eight `0x0025` values
and two `0x0020` values. Any change to this encoding requires a test or direct
comparison with the official `TakerTraitsLib.build` result.

## Guarded failure behavior

The browser must surface recognizable failures for stale volatility, stale
Uniswap observations, insufficient maximum input, and missing Aqua push state.
These are safety reverts, not reasons to bypass the corresponding guard.

- volatility must be refreshed within its one-hour policy;
- the latest Uniswap observation must be at most 120 seconds old;
- inventory-aware repricing may require Bob to approve a higher maximum payment;
- a reverted simulation must not prompt a wallet transaction or move funds.

## Checkpoints

### Checkpoint 1 — Live Alice and Bob controls

Add wallet detection, Base Sepolia switching, live balances, Alice's maker
actions, Bob's protected exact-output purchase, transaction confirmation links,
and the canonical deployed order.

Suggested commit:

```text
feat: enable live maker and trader workflows
```

### Checkpoint 2 — Demo readiness and record

Add named upstream error decoding, operator-side IV/TWAP refresh controls, the
correct 22-byte taker encoding, documentation, and successful-settlement
acceptance evidence.

Suggested commit:

```text
docs: record live wallet settlement workflow
```

## Exit gate

- Alice can mint additional collateralized CALL and expose it through Aqua;
- Bob can approve avUSD and receive CALL through the modified SwapVM router;
- real wallet balances and Aqua virtual balances move consistently;
- stale input and maximum-payment guards remain enforced and understandable;
- `npm run build` succeeds;
- populated `.env` files and credentials remain ignored;
- commits and pushes remain human-controlled unless explicitly requested.
