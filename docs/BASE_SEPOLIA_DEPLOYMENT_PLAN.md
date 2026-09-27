# Base Sepolia deployment plan

## Scope

This is the ordered deployment plan for public hackathon evidence. It contains
no private keys, live addresses created by AquaVol, or authorization to
broadcast transactions.

## Network and asset profile

- Chain: Base Sepolia (`84532`).
- Underlying: canonical Base Sepolia WETH when faucet balance permits.
- Quote: clearly labeled AquaVol DemoUSDC with controlled test minting.
- Spot market: WETH/DemoUSDC pool created through the official Uniswap V3
  factory and seeded near 3,800 DemoUSDC per WETH.
- Comparison only: existing canonical WETH/Circle test-USDC 0.30% pool.

The official Uniswap V3 Base deployment page was rechecked on 2026-09-26 and
lists factory `0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24`, position manager
`0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2`, SwapRouter02
`0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4`, and WETH
`0x4200000000000000000000000000000000000006` for Base Sepolia. Recheck the
[official registry](https://developers.uniswap.org/docs/protocols/v3/deployments/v3-base-deployments)
and deployed code during every preflight rather than treating this record as
permanent configuration.

Public deployment amounts MAY be smaller than local canonical inventory when
testnet WETH is scarce, but per-WETH strike, premium, decimals, and accounting
must remain identical. The final amounts require a reviewed deployment prompt.

## Ordered stages

1. Reverify chain ID, official Uniswap addresses, code hashes, token addresses,
   and deployer balance.
2. Deploy DemoUSDC with explicit faucet/minter controls and public labeling.
3. Resolve or create the WETH/DemoUSDC V3 pool through the official factory.
4. Initialize the pool, increase observation capacity, and add bounded demo
   liquidity through the official position manager.
5. Allow the complete TWAP window to elapse and write recent observations.
6. Deploy and verify `UniswapV3TwapOracle` with immutable pool guards.
7. Deploy and verify the bounded volatility registry.
8. Deploy and verify `OptionSeries`, exact-source Aqua, and
   `AquaVolSwapVMRouter` in their dependency order.
9. Write collateralized CALL, approve Aqua, encode one strategy, and ship
   virtual CALL/DemoUSDC balances.
10. Quote and settle a public trade, then record real and virtual balance
    changes, events, transaction hashes, and explorer links.
11. Run a read-only verification script against the deployment manifest.

## Implemented preflight boundary

Prompt 0010 checkpoint 2 adds a preflight that reads `OPERATOR_ADDRESS` rather
than the signing key. It checks chain ID, the operator's configured minimum gas
balance, dependency bytecode and code hashes, the official 0.30% fee-tier tick
spacing, position-manager and router factory/WETH bindings, and WETH decimals.
The script has no broadcast path. Later state-changing scripts must separately
prove that the signing key derives the reviewed operator address.

## Completed fork rehearsal

Prompt 0010 checkpoint 3 rehearses all ordered stages on pinned Base Sepolia
block `47,324,978`. It uses the official Uniswap deployments to create and
mature a local WETH/avUSD pool, deploys exact pinned Aqua and the AquaVol graph,
ships the position, and settles a distinct-taker trade with inventory repricing.
See [the rehearsal record](BASE_SEPOLIA_REHEARSAL.md). Its addresses and state
are fork-local and MUST NOT be placed in the public deployment manifest.

## Operational rules

- Use one dedicated testnet-only operator for deployer, volatility updater,
  writer, and Aqua maker, plus a distinct browser-connected trader. This is a
  disclosed hackathon simplification, not a production role model.
- Prefer an encrypted Foundry keystore for the operator; an ignored local
  `contracts/.env` is acceptable for the disposable test identity. Never print
  or commit a private key, mnemonic, populated `.env`, or provider credential.
- Fund both identities with Base Sepolia ETH for their own transactions. Do not
  confuse Ethereum Sepolia ETH with Base Sepolia ETH.
- Broadcast only from a separately reviewed deployment prompt.
- Store chain ID, source commit, compiler settings, constructor arguments,
  addresses, transactions, and verification status in a versioned manifest.
- Treat pool initialization and initial liquidity as economic configuration;
  show the exact values before broadcasting.
- Keep local-fork demo evidence available if the public RPC, explorer, or pool
  observation history is unavailable during judging.
- Treat each state-changing stage as separately authorized. Approval to deploy
  infrastructure does not authorize pool initialization, liquidity provision,
  strategy shipping, or a trader transaction.
