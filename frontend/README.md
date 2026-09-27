# Voltrix frontend

React, TypeScript, and Vite strategy workspace for the Voltrix Base Sepolia
options market.

```bash
npm install
npm run build
npm run dev
```

The WETH 4,000 CALL expiring 2026-10-04 is the only deployed series. Its
supply, collateral, and volatility are read from Base Sepolia. Other strikes,
expiries, every PUT, multi-leg presets, and payoff projections are explicitly
labelled simulations.

No private key is needed. `.env.example` contains an optional public RPC
override. For static hosting, use `frontend` as the project root, `npm run
build` as the build command, and `dist` as the output directory.
