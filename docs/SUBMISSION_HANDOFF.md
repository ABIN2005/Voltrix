# AquaVol submission handoff

## One-line description

AquaVol is a fully collateralized onchain WETH call market whose self-custodial
Aqua liquidity is priced by custom SwapVM instructions using a guarded Uniswap
V3 TWAP, Black-Scholes fair value, and live inventory risk.

## Why Aqua and SwapVM matter

The maker writes a real covered CALL by locking WETH in `OptionSeries`, then
ships virtual CALL and avUSD balances to Aqua without depositing that inventory
into an application vault. The modified SwapVM router executes two custom
instructions: `0xd1` computes strategy-bound fair value and `0xd2` applies
spread plus live Aqua inventory exposure. After a purchase reduces virtual
CALL inventory, the exact same immutable strategy produces a higher next ask.

## Public proof

- Network: Base Sepolia (`84532`)
- Strategy hash: `0x1a38d471dce4c9cc7a425010f584dd7ebaf5e0bbcdb42a67506dac1d91e465f5`
- Public trade: `0xb49b7574aa15a92cb96fb6b804279ca321488dcd1b43a8c6bb780a9dd1cf7379`
- Trader paid: 0.779818 avUSD
- Trader received: 0.01 CALL
- Next 0.01 CALL ask: 0.815649 avUSD
- Aqua balances: 0.10 → 0.09 CALL; 50 → 50.779818 avUSD
- Series collateral/supply after trade: 0.10 WETH / 0.10 CALL
- Final guarded TWAP: 3,842.159899 avUSD/WETH

Full addresses and transaction evidence are in
[`BASE_SEPOLIA_DEPLOYMENT.md`](BASE_SEPOLIA_DEPLOYMENT.md).

## Qualification mapping

### 1inch Aqua/SwapVM

- Official pinned Aqua source is deployed without modification.
- The public strategy settles through Aqua and a modified official SwapVM
  router.
- Custom opcodes `0xd1` and `0xd2` are exercised by the public trade.
- Real Base Sepolia token transfers and Aqua virtual-balance changes are
  demonstrated and reconciled.
- Tests, scripts, public transactions, and multi-commit history demonstrate the
  complete position.

### Uniswap

- The project uses the official Base Sepolia V3 factory, position manager, and
  SwapRouter02.
- The guarded oracle reads a project-seeded WETH/avUSD V3 pool.
- Direct integration-code links are in the root README.
- Required repository feedback is in [`FEEDBACK.md`](../FEEDBACK.md).
- The project owner must still complete the external Uniswap feedback form.

## Three-minute demo sequence

1. Show the frontend's live Base Sepolia contract-read strip.
2. Build a spread or straddle and show the payoff react immediately.
3. Explain that only the labelled WETH 4,000 CALL is deployed.
4. Show Uniswap TWAP → pricing → custom SwapVM → Aqua settlement.
5. Open the public trade proving 0.779818 avUSD for 0.01 CALL.
6. Show inventory at 0.09 CALL / 50.779818 avUSD and the higher next ask.
7. End with deployed-contract links and 135 passing Foundry tests.

## Manual submission checklist

- [ ] Build and deploy the frontend.
- [ ] Add the live frontend URL to the root README and ETHGlobal submission.
- [x] Complete the Uniswap Developer Feedback Form with the public
      `FEEDBACK.md` link.
- [ ] Record and upload the demo video.
- [ ] Add the video URL and final submission URL to the README.
- [ ] Select the intended 1inch and Uniswap prize tracks.
- [ ] Confirm the public GitHub default branch contains the latest checkpoint.
- [ ] Confirm no `.env`, private key, broadcast cache, or reference-only files
      appear in GitHub.
- [ ] Run `forge fmt --check`, `forge build`, and `forge test` one final time.
- [ ] Open every BaseScan and repository link in an incognito browser.

## Honest limitations

This is unaudited hackathon software using a project-issued demo quote token
and project-seeded testnet liquidity. One disposable operator consolidates the
deployer, writer, maker, and volatility-updater roles. The TWAP freshness guard
requires recent pool observations. These choices are disclosed and are not a
production security model.
