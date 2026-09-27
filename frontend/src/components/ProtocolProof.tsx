import { deployment, shortAddress } from "../data/deployment";

const flow = [
  { id: "01", name: "Uniswap V3", detail: "A 30-minute WETH / avUSD TWAP supplies a manipulation-resistant spot price.", tag: "Spot input" },
  { id: "02", name: "Black–Scholes", detail: "Spot, strike, time and on-chain volatility produce the option's fair value.", tag: "Pricing engine" },
  { id: "03", name: "Custom SwapVM", detail: "Inventory skew and spread turn fair value into an executable ask.", tag: "Opcodes D1 · D2" },
  { id: "04", name: "Aqua", detail: "Tokens move directly between maker and taker — no pooled custody.", tag: "Settlement layer" },
];

const contracts = [
  ["Aqua", deployment.addresses.aqua],
  ["Modified SwapVM router", deployment.addresses.router],
  ["Pricing engine", deployment.addresses.pricing],
  ["Uniswap TWAP oracle", deployment.addresses.oracle],
  ["WETH 4,000 CALL", deployment.addresses.optionSeries],
  ["Uniswap V3 pool", deployment.addresses.pool],
] as const;

export function DeploymentContracts() {
  return <section className="section contracts-section" aria-label="Public Base Sepolia deployment">
    <div className="panel">
      <div className="panel-heading"><div><span className="eyebrow">Public deployment</span><h3>Verified contracts</h3></div><span className="network-chip"><i className="pulse" />{deployment.network}</span></div>
      <div className="contract-grid">{contracts.map(([name, address]) =>
        <a href={`${deployment.explorer}/address/${address}`} target="_blank" rel="noreferrer" key={name}>
          <span>{name}</span><strong>{shortAddress(address)}</strong><b aria-hidden="true">↗</b>
        </a>)}</div>
    </div>
  </section>;
}

export function ProtocolProof() {
  const repricing = (deployment.lastAsk / deployment.settledAsk - 1) * 100;
  return <section className="section" id="how">
    <div className="section-head centered">
      <div>
        <span className="eyebrow">How it works</span>
        <h2>One trade.<br/><span className="gradient-text">Four verifiable layers.</span></h2>
        <p>Every Voltrix quote is computed and settled on-chain. The live market is backed by a real Base Sepolia trade with reconciled balances.</p>
      </div>
    </div>

    <ol className="flow-grid">
      {flow.map((step) => <li className="flow-card" key={step.id}>
        <div className="flow-top"><span className="flow-index">{step.id}</span><small>{step.tag}</small></div>
        <h3>{step.name}</h3><p>{step.detail}</p>
      </li>)}
    </ol>

    <div className="evidence-grid" id="proof">
      <article className="panel trade-proof">
        <div className="evidence-title"><span className="live-badge">Settled on-chain</span><span>Base Sepolia · 84532</span></div>
        <h3>0.01 CALL purchased</h3>
        <div className="trade-value">{deployment.settledAsk}<small> avUSD paid</small></div>
        <div className="reprice-row">
          <div><small>Settled ask</small><strong>{deployment.settledAsk}</strong></div>
          <span aria-hidden="true">→</span>
          <div><small>Next ask</small><strong>{deployment.lastAsk}</strong></div>
          <em>+{repricing.toFixed(2)}%</em>
        </div>
        <p>CALL inventory fell while quote inventory increased, so the same immutable strategy returned a higher ask for the next buyer.</p>
        <a className="evidence-link" href={`${deployment.explorer}/tx/${deployment.tradeTx}`} target="_blank" rel="noreferrer">Inspect the trade on BaseScan <span aria-hidden="true">↗</span></a>
      </article>

      <article className="panel balance-card">
        <div className="panel-heading"><div><span className="eyebrow">State transition</span><h3>Aqua virtual balances</h3></div><span className="proof-pill">Reconciled</span></div>
        <div className="balance-head"><span>Asset</span><span>Before</span><span>After</span><span>Change</span></div>
        <div className="balance-row"><strong>CALL</strong><span>0.10</span><span>0.09</span><em className="down">−0.01</em></div>
        <div className="balance-row"><strong>avUSD</strong><span>50.000000</span><span>50.779818</span><em className="up">+0.779818</em></div>
        <div className="balance-row"><strong>WETH collateral</strong><span>0.10</span><span>0.10</span><em>Unchanged</em></div>
        <p className="panel-note">OptionSeries collateral remains equal to outstanding CALL supply after settlement.</p>
      </article>
    </div>
  </section>;
}
