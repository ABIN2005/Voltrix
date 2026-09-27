# Prompt 0003: Build the mathematical reference

- Date: 2026-09-26
- Input state: AquaVol MVP specifications drafted and reviewed
- Authorized scope: Python reference model, tests, and vectors only

## Human approval

Adopt these MVP defaults:

- one writer per option series;
- European covered calls;
- a 24-hour post-expiry exercise window;
- transferable CALL tokens after expiry, with Aqua trading disabled at expiry;
- exact-output CALL purchases and exact-input CALL sell-backs;
- 10 WETH collateral creating 10 CALL tokens;
- 4,000 USDC strike;
- 3,800 USDC initial mock spot;
- seven days to expiry;
- 64% annualized implied volatility;
- 20% inventory gamma;
- 1% half-spread;
- 10 CALL and 5,000 virtual USDC in the canonical Aqua strategy;
- administrator-controlled demo spot and volatility inputs;
- Base Sepolia for public swap evidence;
- a deterministic local fork for the exercise replay;
- no required backend in the canonical MVP.

## Task

Create an independent Python Black-Scholes reference using only the Python
standard library. It must:

- price European calls with risk-free rate and dividend yield fixed to zero;
- expose `d1`, `d2`, their normal CDF values, intrinsic value, and call value;
- define expiry and zero-volatility behavior;
- reject invalid inputs;
- generate versioned JSON vectors with decimal and normalized integer values;
- cover moneyness, time, volatility, expiry, CDF tails, and inventory pricing;
- verify the canonical fair value near 60.29 USDC;
- provide deterministic regeneration and test commands.

Update the specifications to record the approved defaults. Do not implement
Solidity, Aqua, SwapVM, TypeScript, or frontend code in this phase.

## Output

```text
python/
  pyproject.toml
  README.md
  aquavol_math/
    __init__.py
    black_scholes.py
    generate_vectors.py
  tests/
    test_black_scholes.py

test/
  vectors/
    black_scholes-v1.json
```

## Repository boundary

Do not stage files, commit changes, or push to a remote repository.

