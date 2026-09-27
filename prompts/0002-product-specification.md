# Prompt 0002: Specify the AquaVol MVP

- Date: 2026-09-26
- Input state: foundation approved; no application code exists
- Requested output: public product specifications only

## Human request

Define AquaVol as a focused hackathon MVP for programmable options market
making. Use React, TypeScript, Vite, Node.js, Solidity, Foundry, Base Sepolia,
and a Python Black-Scholes reference model.

The product should combine:

- a fully collateralized European covered-call token;
- Aqua-managed CALL/USDC market-making liquidity;
- a modified SwapVM router;
- a fair-value instruction based on Black-Scholes;
- an inventory-skew instruction based on current Aqua balances;
- visible onchain token settlement.

Create specifications for the product, option lifecycle, pricing model,
Aqua/SwapVM integration, security invariants, and final demonstration. Do not
generate application or contract code.

## Required corrections and constraints

- Use React with Vite, not Next.js.
- Use one maker, one trader, one strike, and one expiry for the canonical MVP.
- Treat additional strikes as a stretch goal.
- Use WETH as the underlying, USDC as the quote asset, and an 18-decimal CALL
  token representing the right to buy one WETH per whole token.
- Keep option collateral separate from Aqua market-making liquidity.
- Stop trading at expiry and permit exercise only during a defined post-expiry
  exercise window.
- Use a mock spot oracle and an administrator-updated volatility registry for
  the deterministic demo, and disclose both trust assumptions.
- Set the risk-free rate and dividend yield to zero for the MVP.
- For spot 3,800, strike 4,000, seven days, and 64% annualized volatility, use
  approximately 60.29 USDC as the reference fair value, subject to the canonical
  Python vector.
- Define supported numeric domains, rounding behavior, oracle freshness,
  overflow protections, and approximation tolerances before implementation.
- Keep Python independent from the live transaction path.
- Do not require a backend for the canonical demo unless a later specification
  proves it necessary.

## Output files

Create:

```text
specs/01-product.md
specs/02-option-lifecycle.md
specs/03-pricing-model.md
specs/04-aqua-swapvm-integration.md
specs/05-security-invariants.md
specs/06-demo-acceptance.md
```

Each document must identify its status, normative requirements, unresolved
items, and acceptance conditions. The specifications remain drafts until a
human explicitly approves them.

## AI task boundary

Do not install dependencies, scaffold packages, write implementation code,
stage files, commit changes, or push to a remote repository.

