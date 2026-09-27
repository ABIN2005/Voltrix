import { useState } from "react";
import { concatHex, createPublicClient, createWalletClient, custom, formatEther, formatUnits, getAddress, http, parseEther, parseUnits, toHex, type Address, type EIP1193Provider, type Hash, type Hex } from "viem";
import { baseSepolia } from "viem/chains";
import { deployment, shortAddress } from "../data/deployment";

const erc20Abi = [{ type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] }] as const;
const wethAbi = [
  { type: "function", name: "deposit", stateMutability: "payable", inputs: [], outputs: [] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
] as const;
const seriesAbi = [
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
  { type: "function", name: "write", stateMutability: "nonpayable", inputs: [{ type: "uint256" }], outputs: [] },
] as const;
const aquaAbi = [{ type: "function", name: "push", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "address" }, { type: "bytes32" }, { type: "address" }, { type: "uint256" }], outputs: [] }] as const;
const aquaBalanceAbi = [{ type: "function", name: "safeBalances", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }, { type: "bytes32" }, { type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }, { type: "uint256" }] }] as const;
const wethDepositSelector = "0xd0e30db0" as const;
const volatilityRegistryAbi = [{ type: "function", name: "setVolatility", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [] }] as const;
const uniswapRouterAbi = [{
  type: "function",
  name: "exactInputSingle",
  stateMutability: "payable",
  inputs: [{
    type: "tuple",
    components: [
      { name: "tokenIn", type: "address" },
      { name: "tokenOut", type: "address" },
      { name: "fee", type: "uint24" },
      { name: "recipient", type: "address" },
      { name: "amountIn", type: "uint256" },
      { name: "amountOutMinimum", type: "uint256" },
      { name: "sqrtPriceLimitX96", type: "uint160" },
    ],
  }],
  outputs: [{ name: "amountOut", type: "uint256" }],
}] as const;
const liveOrder = {
  maker: deployment.addresses.operator,
  traits: 28948022309345504152553859025372987423956659195481894094225317213215909740544n,
  // Canonical program from the publicly settled Base Sepolia AquaVol trade.
  data: "0x7f3c414aef81caf377ff34a419ec388105fba117f47584005b5c0f90f292c811016e70e37e3ba9dcd1a00000000000000000000000007f3c414aef81caf377ff34a419ec388105fba117000000000000000000000000f47584005b5c0f90f292c811016e70e37e3ba9dc0000000000000000000000002d2bfade5ad73c946fdca2a882a21e542a568903000000000000000000000000f2537463ddea54eea205bD183a9e303bDe02C37e0000000000000000000000000000000000000000000000000000000000000e10d2c00000000000000000000000007f3c414aef81caf377ff34a419ec388105fba117000000000000000000000000f47584005b5c0f90f292c811016e70e37e3ba9dc0000000000000000000000002d2bfade5ad73c946fdca2a882a21e542a568903000000000000000000000000000000000000000000000000016345785d8a000000000000000000000000000000000000000000000000000002c68af0bb140000000000000000000000000000000000000000000000000000002386f26fc1000002080000000000000004" as Hex,
} as const;
const routerAbi = [
  { type: "error", name: "LatestObservationTooOld", inputs: [{ type: "uint32" }, { type: "uint32" }] },
  { type: "error", name: "VolatilityStale", inputs: [{ type: "uint256" }, { type: "uint256" }] },
  { type: "error", name: "AquaBalanceInsufficientAfterTakerPush", inputs: [{ type: "uint256" }, { type: "uint256" }, { type: "uint256" }] },
  { type: "error", name: "TakerTraitsExceedingMaxInputAmount", inputs: [{ name: "amountIn", type: "uint256" }, { name: "amountInMax", type: "uint256" }] },
  { type: "function", name: "hash", stateMutability: "view", inputs: [{ type: "tuple", components: [{ type: "address", name: "maker" }, { type: "uint256", name: "traits" }, { type: "bytes", name: "data" }] }], outputs: [{ type: "bytes32" }] },
  { type: "function", name: "swap", stateMutability: "payable", inputs: [{ type: "tuple", components: [{ type: "address", name: "maker" }, { type: "uint256", name: "traits" }, { type: "bytes", name: "data" }] }, { type: "uint256" }, { type: "bytes" }], outputs: [{ type: "uint256" }, { type: "uint256" }, { type: "bytes32" }] },
] as const;
const buildExactOutputBuyData = (maximumInput: bigint) => concatHex([
  // 10 uint16 slice offsets followed by uint16 flags. Eight 0x0025 offsets,
  // two 0x0020 offsets, then 0x0040 (transferFrom taker + Aqua push).
  "0x00250025002500250025002500250025002000200040",
  toHex(maximumInput, { size: 32 }),
  toHex(BigInt(Math.floor(Date.now() / 1000) + 300), { size: 5 }),
]);
const publicClient = createPublicClient({ chain: baseSepolia, transport: http(import.meta.env.VITE_BASE_SEPOLIA_RPC_URL || deployment.rpcUrl) });
type Balances = { eth: string; avUsd: string; call: string };
type WalletRole = "maker" | "buyer";
type Step = { id: string; title: string; detail: string; run: () => Promise<boolean> };

export function WalletPanel() {
  const [role, setRole] = useState<WalletRole>();
  const [account, setAccount] = useState<Address>();
  const [balances, setBalances] = useState<Balances>();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [amount, setAmount] = useState("0.01");
  const [buyAmount, setBuyAmount] = useState("0.01");
  const [maxPayment, setMaxPayment] = useState("2.00");
  const [action, setAction] = useState("");
  const [lastTx, setLastTx] = useState<Hash>();
  const [done, setDone] = useState<Record<string, boolean>>({});
  const alice = account?.toLowerCase() === deployment.addresses.operator.toLowerCase();
  const makerWalletMismatch = role === "maker" && !!account && !alice;

  const refresh = async (address: Address) => {
    const [eth, avUsd, call] = await Promise.all([
      publicClient.getBalance({ address }),
      publicClient.readContract({ address: deployment.addresses.avUsd, abi: erc20Abi, functionName: "balanceOf", args: [address] }),
      publicClient.readContract({ address: deployment.addresses.optionSeries, abi: erc20Abi, functionName: "balanceOf", args: [address] }),
    ]);
    setBalances({ eth: Number(formatEther(eth)).toFixed(4), avUsd: Number(formatUnits(avUsd, 6)).toFixed(6), call: Number(formatEther(call)).toFixed(4) });
  };

  const connect = async () => {
    const provider = (window as Window & { ethereum?: EIP1193Provider }).ethereum;
    if (!provider) return setError("MetaMask was not detected.");
    setBusy(true); setError("");
    try {
      const wallet = createWalletClient({ chain: baseSepolia, transport: custom(provider) });
      const [selected] = await wallet.requestAddresses();
      try {
        await wallet.switchChain({ id: deployment.chainId });
      } catch {
        await provider.request({
          method: "wallet_addEthereumChain",
          params: [{
            chainId: "0x14a34",
            chainName: "Base Sepolia",
            nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
            rpcUrls: [deployment.rpcUrl],
            blockExplorerUrls: [deployment.explorer],
          }],
        });
        await wallet.switchChain({ id: deployment.chainId });
      }
      const checked = getAddress(selected);
      setAccount(checked);
      await refresh(checked);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Wallet connection failed.");
    } finally { setBusy(false); }
  };

  const transact = async (label: string, send: (wallet: ReturnType<typeof createWalletClient>, owner: Address) => Promise<Hash>) => {
    const provider = (window as Window & { ethereum?: EIP1193Provider }).ethereum;
    if (!provider || !account) return false;
    setAction(label); setError(""); setLastTx(undefined);
    try {
      const wallet = createWalletClient({ account, chain: baseSepolia, transport: custom(provider) });
      const hash = await send(wallet, account);
      setLastTx(hash);
      await publicClient.waitForTransactionReceipt({ hash });
      await refresh(account);
      return true;
    } catch (cause) {
      console.error(`${label} failed:`, cause);
      setError(cause instanceof Error ? cause.message : `${label} failed.`);
      return false;
    } finally { setAction(""); }
  };
  const runStep = async (id: string, run: () => Promise<boolean>) => {
    if (await run()) setDone((all) => ({ ...all, [id]: true }));
  };
  const units = () => parseEther(amount || "0");
  // Preflight through the app's read RPC, then submit directly to MetaMask.
  // This separates a configuration/contract failure from a wallet-RPC failure.
  const wrapWeth = () => transact("Wrapping ETH", async (_wallet, owner) => {
    const provider = (window as Window & { ethereum?: EIP1193Provider }).ethereum;
    if (!provider) throw new Error("MetaMask was not detected.");
    const [chainId, code] = await Promise.all([
      provider.request({ method: "eth_chainId" }),
      publicClient.getCode({ address: deployment.addresses.weth }),
    ]);
    if (chainId !== "0x14a34") throw new Error(`Switch MetaMask to Base Sepolia (current chain: ${chainId}).`);
    if (!code || code === "0x") throw new Error(`No WETH contract found at ${deployment.addresses.weth} on Base Sepolia.`);

    const value = `0x${units().toString(16)}` as `0x${string}`;
    console.info("wrapWeth preflight", {
      owner,
      chainId,
      weth: deployment.addresses.weth,
      amountWei: units().toString(),
      value,
      codePresent: true,
    });
    await publicClient.call({
      account: owner,
      to: deployment.addresses.weth,
      data: wethDepositSelector,
      value: units(),
    });
    return provider.request({
      method: "eth_sendTransaction",
      params: [{
        from: owner,
        to: deployment.addresses.weth,
        data: wethDepositSelector, // WETH9 deposit()
        value,
      }],
    }) as Promise<Hash>;
  });
  const watchCall = async () => {
    const provider = (window as Window & { ethereum?: EIP1193Provider }).ethereum;
    if (!provider) return false;
    try {
      await provider.request({ method: "wallet_watchAsset", params: { type: "ERC20", options: { address: deployment.addresses.optionSeries, symbol: "avWETH-4000-C", decimals: 18 } } });
      return true;
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Adding the token failed.");
      return false;
    }
  };
  const authorizeInventory = () => transact("Authorizing full inventory", async (wallet, owner) => {
    const [virtualCall] = await publicClient.readContract({ address: deployment.addresses.aqua, abi: aquaBalanceAbi, functionName: "safeBalances", args: [deployment.addresses.operator, deployment.addresses.router, deployment.strategyHash, deployment.addresses.optionSeries, deployment.addresses.avUsd] });
    return wallet.writeContract({ account: owner, chain: null, address: deployment.addresses.optionSeries, abi: seriesAbi, functionName: "approve", args: [deployment.addresses.aqua, virtualCall] });
  });
  const refreshVolatility = () => transact("Refreshing 64% onchain IV", (wallet, owner) => wallet.writeContract({
    account: owner,
    chain: null,
    address: deployment.addresses.volatilityRegistry,
    abi: volatilityRegistryAbi,
    functionName: "setVolatility",
    args: [deployment.addresses.optionSeries, parseEther(String(deployment.volatility))],
  }));
  const approveTwapRefresh = () => transact("Approving TWAP refresh budget", (wallet, owner) => wallet.writeContract({
    account: owner,
    chain: null,
    address: deployment.addresses.avUsd,
    abi: wethAbi,
    functionName: "approve",
    args: [deployment.addresses.uniswapRouter, parseUnits("10", 6)],
  }));
  const refreshTwap = () => transact("Refreshing Uniswap TWAP observation", (wallet, owner) => wallet.writeContract({
    account: owner,
    chain: null,
    address: deployment.addresses.uniswapRouter,
    abi: uniswapRouterAbi,
    functionName: "exactInputSingle",
    args: [{
      tokenIn: deployment.addresses.avUsd,
      tokenOut: deployment.addresses.weth,
      fee: 3000,
      recipient: owner,
      amountIn: parseUnits("1", 6),
      amountOutMinimum: 200_000_000_000_000n,
      sqrtPriceLimitX96: 0n,
    }],
  }));
  const buyCall = () => transact("Buying live CALL", async (wallet, owner) => {
    const amountOut = parseEther(buyAmount || "0");
    const maximumInput = parseUnits(maxPayment || "0", 6);
    const orderHash = await publicClient.readContract({ address: deployment.addresses.router, abi: routerAbi, functionName: "hash", args: [liveOrder] });
    if (orderHash.toLowerCase() !== deployment.strategyHash.toLowerCase()) throw new Error("The deployed Aqua strategy did not match its expected hash.");
    const { request } = await publicClient.simulateContract({
      account: owner,
      address: deployment.addresses.router,
      abi: routerAbi,
      functionName: "swap",
      args: [liveOrder, amountOut, buildExactOutputBuyData(maximumInput)],
    });
    return wallet.writeContract({ ...request, account: owner, chain: null });
  });

  const makerSteps: Step[] = [
    { id: "wrap", title: "Wrap ETH", detail: "Convert ETH into WETH", run: wrapWeth },
    { id: "approve-weth", title: "Approve WETH", detail: `Let OptionSeries lock exactly ${amount || "0"} WETH`, run: () => transact("Approving WETH", (wallet, owner) => wallet.writeContract({ account: owner, chain: null, address: deployment.addresses.weth, abi: wethAbi, functionName: "approve", args: [deployment.addresses.optionSeries, units()] })) },
    { id: "write", title: "Write CALL", detail: "Lock WETH and mint CALL tokens", run: () => transact("Writing CALL", (wallet, owner) => wallet.writeContract({ account: owner, chain: null, address: deployment.addresses.optionSeries, abi: seriesAbi, functionName: "write", args: [units()] })) },
    { id: "watch-maker", title: "Add to MetaMask", detail: "Track the CALL token", run: watchCall },
    { id: "approve-call", title: "Approve Aqua", detail: "Allow Aqua to move the exact CALL amount", run: () => transact("Approving CALL", (wallet, owner) => wallet.writeContract({ account: owner, chain: null, address: deployment.addresses.optionSeries, abi: seriesAbi, functionName: "approve", args: [deployment.addresses.aqua, units()] })) },
    { id: "push", title: "Push to Aqua", detail: "Increase virtual CALL inventory", run: () => transact("Adding Aqua liquidity", (wallet, owner) => wallet.writeContract({ account: owner, chain: null, address: deployment.addresses.aqua, abi: aquaAbi, functionName: "push", args: [deployment.addresses.operator, deployment.addresses.router, deployment.strategyHash, deployment.addresses.optionSeries, units()] })) },
    { id: "authorize", title: "Authorize inventory", detail: "Cover the full virtual CALL balance", run: authorizeInventory },
    { id: "volatility", title: "Refresh 64% IV", detail: "Required before live CALL buys", run: refreshVolatility },
    { id: "twap-budget", title: "Approve TWAP budget", detail: "Let the Uniswap router spend 10 avUSD", run: approveTwapRefresh },
    { id: "twap", title: "Refresh TWAP", detail: "Swap 1 avUSD for a fresh observation", run: refreshTwap },
  ];
  const buyerSteps: Step[] = [
    { id: "approve-avusd", title: "Approve avUSD", detail: `Let the SwapVM router spend up to ${maxPayment || "0"} avUSD`, run: () => transact("Approving avUSD", (wallet, owner) => wallet.writeContract({ account: owner, chain: null, address: deployment.addresses.avUsd, abi: wethAbi, functionName: "approve", args: [deployment.addresses.router, parseUnits(maxPayment || "0", 6)] })) },
    { id: "buy", title: "Buy live CALL", detail: `Receive exactly ${buyAmount || "0"} CALL, or revert above your max`, run: buyCall },
    { id: "watch-buyer", title: "Add to MetaMask", detail: "Track avWETH-4000-C after settlement", run: watchCall },
  ];
  const steps = role === "maker" && alice ? makerSteps : role === "buyer" && account ? buyerSteps : [];
  const completed = steps.filter((step) => done[step.id]).length;
  const chooseRole = (next: WalletRole) => { setRole(next); setError(""); };

  return <section className="section" id="trade">
    <div className="section-head">
      <div><span className="eyebrow">Trade</span><h2>Pick a side.<br/><span className="gradient-text">Execute on-chain.</span></h2></div>
      <p>Every transaction is signed in MetaMask on {deployment.network}. Voltrix never takes custody of your assets.</p>
    </div>

    <div className="trade-shell panel">
      <div className="role-grid" role="radiogroup" aria-label="Choose your role">
        <button role="radio" aria-checked={role === "maker"} className={role === "maker" ? "role-card active" : "role-card"} onClick={() => chooseRole("maker")}>
          <span className="role-icon maker" aria-hidden="true">◆</span>
          <span><strong>Liquidity Maker</strong><small>Write covered CALLs and supply them to the market. Requires the operator wallet.</small></span>
        </button>
        <button role="radio" aria-checked={role === "buyer"} className={role === "buyer" ? "role-card active" : "role-card"} onClick={() => chooseRole("buyer")}>
          <span className="role-icon buyer" aria-hidden="true">▲</span>
          <span><strong>Option Buyer</strong><small>Buy the live WETH $4,000 CALL at the on-chain ask.</small></span>
        </button>
      </div>

      <div className="wallet-bar">
        <div className="wallet-id">
          <span className={account ? "avatar connected" : "avatar"} aria-hidden="true" />
          <div><small>MetaMask</small><strong>{account ? shortAddress(account) : "Not connected"}</strong></div>
        </div>
        {account && <dl className="wallet-balances">
          <div><dt>Base ETH</dt><dd>{balances?.eth ?? "—"}</dd></div>
          <div><dt>avUSD</dt><dd>{balances?.avUsd ?? "—"}</dd></div>
          <div><dt>Live CALL</dt><dd>{balances?.call ?? "—"}</dd></div>
        </dl>}
        <button className={account ? "btn btn-ghost" : "btn btn-primary"} onClick={() => account ? void refresh(account) : void connect()} disabled={busy || !role}>
          {busy ? "Connecting…" : account ? "↻ Refresh balances" : role ? "Connect MetaMask" : "Choose a role first"}
        </button>
      </div>

      {error && <div className="alert alert-error" role="alert" title={error}><strong>Something went wrong</strong><span>{error}</span></div>}
      {makerWalletMismatch && <div className="alert alert-warn"><strong>Liquidity Maker requires the operator wallet.</strong><span>Switch MetaMask to {shortAddress(deployment.addresses.operator)} and reconnect.</span></div>}

      {steps.length > 0 && <div className="console">
        <div className="console-head">
          <div>
            <span className="eyebrow">{role === "maker" ? "Liquidity maker" : "Option buyer"}</span>
            <h3>{role === "maker" ? "Write and supply covered CALLs" : "Buy the live WETH $4,000 CALL"}</h3>
            {role === "buyer" && <p>Only this deployed CALL is executable. The operator must first send this wallet demo avUSD, and the TWAP must be fresh.</p>}
          </div>
          {role === "maker"
            ? <label className="field">CALL amount<input value={amount} onChange={(event) => setAmount(event.target.value)} type="number" min="0.001" step="0.01"/></label>
            : <div className="field-row">
              <label className="field">CALL amount<input value={buyAmount} onChange={(event) => setBuyAmount(event.target.value)} type="number" min="0.001" max="0.09" step="0.01"/></label>
              <label className="field">Max avUSD<input value={maxPayment} onChange={(event) => setMaxPayment(event.target.value)} type="number" min="0.01" step="0.01"/></label>
            </div>}
        </div>
        <div className="progress" aria-label={`${completed} of ${steps.length} steps complete`}>
          <div className="progress-track"><span style={{ width: `${(completed / steps.length) * 100}%` }} /></div>
          <small>{completed}/{steps.length} complete</small>
        </div>
        <ol className={role === "maker" ? "stepper" : "stepper stepper-compact"}>
          {steps.map((step, index) => <li key={step.id}>
            <button className={done[step.id] ? "step done" : "step"} disabled={!!action} onClick={() => void runStep(step.id, step.run)}>
              <span className="step-index">{done[step.id] ? "✓" : String(index + 1).padStart(2, "0")}</span>
              <strong>{step.title}</strong>
              <small>{step.detail}</small>
            </button>
          </li>)}
        </ol>
        <div className="console-status">
          <span>{action ? <><i className="spinner" aria-hidden="true" />{action}…</> : role === "maker" ? "Run each numbered transaction in order." : "Approve your maximum payment, then execute the protected buy."}</span>
          {lastTx && <a href={`${deployment.explorer}/tx/${lastTx}`} target="_blank" rel="noreferrer">View transaction ↗</a>}
        </div>
      </div>}
    </div>
  </section>;
}
