# Option lifecycle specification

## Status

- Version: 0.2
- State: approved MVP behavior
- Implementation authorized: isolated OptionSeries contract and tests

## Immutable series identity

Each `OptionSeries` represents exactly one covered European call. Its identity
MUST include:

- writer address;
- WETH underlying address;
- USDC quote address;
- strike price expressed as quote WAD per whole WETH;
- expiry timestamp;
- 24-hour exercise-window duration;
- option-token name and symbol.

The MVP MUST deploy a separate ERC-20 contract for each series. Series terms
MUST NOT change after deployment.

## Units

| Quantity | Unit |
| --- | --- |
| WETH collateral | 18-decimal token units |
| CALL amount | 18-decimal token units |
| Strike | 18-decimal quote value per 1 WETH |
| Exercise payment | 6-decimal USDC token units |
| Time | Unix seconds at lifecycle boundaries |

One whole CALL (`1e18`) MUST represent the right to exchange the strike payment
for one whole WETH (`1e18`). Fractional exercise MUST be supported unless a
later implementation constraint explicitly rejects it.

## Lifecycle states

The state is derived from time rather than mutable administration:

```text
ACTIVE
  block.timestamp < expiry

EXERCISE
  expiry <= block.timestamp < expiry + exerciseWindow

REDEEMABLE
  block.timestamp >= expiry + exerciseWindow
```

There is no administrator-controlled state transition.

## Write

During `ACTIVE`, only the immutable writer MAY write options.

For a requested CALL amount `q`:

1. transfer exactly `q` WETH units from the writer to the series;
2. record the additional written amount;
3. mint exactly `q` CALL units to the writer;
4. emit an event containing writer, collateral amount, and CALL amount.

The write operation MUST revert if the collateral transfer is incomplete.
Fee-on-transfer and rebasing collateral are unsupported.

## Market activation

After writing, the writer MAY approve Aqua for CALL and USDC and ship an
Aqua-backed SwapVM strategy. Shipping does not move the WETH collateral held by
`OptionSeries`.

Docking or exhausting an Aqua strategy stops that market's trading but MUST NOT
change CALL ownership, collateral, expiry, or exercise rights.

## Trading

Trading MUST be permitted only during `ACTIVE`.

Supported directions are:

- trader pays USDC and receives an exact CALL quantity;
- trader supplies an exact CALL quantity and receives USDC.

The market MUST reject:

- purchases exceeding current virtual CALL inventory;
- sell-backs that would increase strategy CALL inventory above its initial
  shipped CALL inventory;
- trades with expired taker deadlines;
- trades violating taker maximum-input or minimum-output thresholds;
- trades at or after series expiry.

Trading transfers CALL ownership but does not move series collateral.

## Exercise

Exercise MUST be permitted only during `EXERCISE`.

For CALL amount `q`:

1. calculate strike USDC using full-precision multiplication and round the
   required payment upward;
2. transfer the required USDC from the holder into `OptionSeries`;
3. burn exactly `q` CALL units from the holder;
4. transfer exactly `q` WETH units to the holder;
5. update exercised and proceeds accounting;
6. emit an exercise event with holder, CALL burned, USDC paid, and WETH sent.

Exercise MUST NOT read spot or volatility. An out-of-the-money holder simply
chooses not to exercise.

Exercise effects MUST complete atomically. The contract MUST prevent
reentrancy across payment, burn, accounting, and WETH delivery.

## Writer redemption

Redemption MUST be permitted only during `REDEEMABLE` and only for the immutable
writer.

Because the MVP has exactly one writer, a single final redemption MAY transfer:

- all unexercised WETH collateral; and
- all USDC strike proceeds received through exercise.

The contract MUST record completion and reject repeated redemption. After
redemption, no exercise or writing is permitted. Outstanding unexercised CALL
tokens have no redemption claim and remain expired evidence only.

## Solvency relationships

Before redemption:

```text
WETH held by series
= totalWritten - totalExercised
```

Subject only to token behavior and already withdrawn final proceeds:

```text
USDC held by series
= cumulative exercise payments
```

At all times before the exercise window closes:

```text
WETH held by series
>= CALL supply that can still be exercised
```

## Required events

The public interface SHOULD emit distinct events for:

- option writing;
- exercise;
- writer redemption.

Events MUST contain amounts in token-native units and enough identifiers to
associate them with the immutable series.

## Lifecycle acceptance

Tests MUST demonstrate:

- write succeeds only with complete WETH collateral;
- one WETH unit mints one CALL unit;
- trading does not change series WETH collateral;
- exercise is rejected before expiry and after the window;
- valid exercise burns CALL, receives USDC, and sends WETH atomically;
- final redemption returns the correct mixture of WETH and USDC;
- repeated exercise with burned tokens and repeated redemption both fail;
- fractional option amounts preserve solvency and rounding rules.

## Approved lifecycle decisions

- The exercise window lasts 24 hours after expiry.
- Aqua trading stops at expiry.
- CALL tokens remain standard transferable ERC-20 tokens after expiry, although
  expired tokens have no exercise or redemption claim after the window closes.
- The public name format is `AquaVol WETH <strike> Call <YYYYMMDD>`.
- The symbol format is `avWETH-<strike>-C-<YYYYMMDD>`.

Prompt 0004 authorizes the isolated `OptionSeries` contract and its Foundry
tests. It does not authorize Aqua, SwapVM, pricing-oracle, or deployment code.
