export const deployment = {
  chainId: 84532,
  network: "Base Sepolia",
  explorer: "https://sepolia.basescan.org",
  // Base's public RPC is rate-limited. This endpoint is used only for public
  // reads/simulations; wallet transactions are still signed by MetaMask.
  rpcUrl: "https://base-sepolia.drpc.org",
  spot: 3842.159899,
  volatility: 0.64,
  liveStrike: 4000,
  liveExpiry: "2026-10-04T03:00:00Z",
  quoteSize: 0.01,
  lastAsk: 0.815649,
  settledAsk: 0.779818,
  addresses: {
    operator: "0xA4A103c574a9bF22Bc49a7Ce3f089508300320d5",
    avUsd: "0xf47584005b5c0F90f292C811016E70e37E3BA9dc",
    weth: "0x4200000000000000000000000000000000000006",
    aqua: "0x170B0d7C534785eAD9Ecbc278B3D87781855D4F9",
    router: "0x8b734D9222D51Aa75C038AB81145FC86D5b4ceb4",
    pricing: "0x68b7036ae9e1266675f226F36d2c764927C84884",
    oracle: "0x2D2bfade5AD73C946fdcA2a882A21E542A568903",
    optionSeries: "0x7F3c414aEf81CAf377fF34A419EC388105fBA117",
    volatilityRegistry: "0xF2537463ddeA54EEa205bD183a9e303bDe02C37e",
    pool: "0x0d9516aA182Aa72284802372afaa943E9E77A6D0",
    uniswapRouter: "0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4",
  },
  tradeTx: "0xb49b7574aa15a92cb96fb6b804279ca321488dcd1b43a8c6bb780a9dd1cf7379",
  strategyHash: "0x1a38d471dce4c9cc7a425010f584dd7ebaf5e0bbcdb42a67506dac1d91e465f5",
} as const;

export const shortAddress = (value: string) =>
  `${value.slice(0, 6)}…${value.slice(-4)}`;
