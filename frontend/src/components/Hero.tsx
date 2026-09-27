import { useEffect, useState } from "react";
import { deployment } from "../data/deployment";

const pad = (value: number) => String(value).padStart(2, "0");

function useCountdown(target: string) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  const seconds = Math.floor(Math.max(new Date(target).getTime() - now, 0) / 1000);
  return [
    { label: "Days", value: Math.floor(seconds / 86_400) },
    { label: "Hrs", value: Math.floor((seconds % 86_400) / 3_600) },
    { label: "Min", value: Math.floor((seconds % 3_600) / 60) },
    { label: "Sec", value: seconds % 60 },
  ];
}

export const expiryLabel = new Date(deployment.liveExpiry).toLocaleDateString("en-GB", {
  day: "2-digit", month: "short", year: "numeric", timeZone: "UTC",
});

export function Hero() {
  const countdown = useCountdown(deployment.liveExpiry);
  const askPerCall = deployment.lastAsk / deployment.quoteSize;

  return <section className="hero" id="top">
    <div className="hero-copy">
      <span className="pill"><i className="pulse" />Live on {deployment.network}</span>
      <h1>On-chain options,<br /><span className="gradient-text">priced in real time.</span></h1>
      <p>
        Voltrix writes fully collateralized ETH calls, prices every quote on-chain with
        Black–Scholes and a guarded Uniswap V3 TWAP, and settles each trade
        self-custodially in a single swap.
      </p>
      <div className="hero-actions">
        <a className="btn btn-primary" href="#trade">Start trading <span aria-hidden="true">→</span></a>
        <a className="btn btn-ghost" href="#strategy">Build a strategy</a>
      </div>
      <dl className="hero-facts">
        <div><dt>Collateral</dt><dd>100%</dd></div>
        <div><dt>Oracle window</dt><dd>30 min</dd></div>
        <div><dt>Custody</dt><dd>Self</dd></div>
      </dl>
    </div>

    <article className="instrument-card">
      <div className="instrument-glow" aria-hidden="true" />
      <header>
        <div><span className="eyebrow">Featured instrument</span><h2>WETH $4,000 CALL</h2></div>
        <span className="live-badge">LIVE</span>
      </header>
      <div className="instrument-price">
        <small>Ask per CALL</small>
        <strong>${askPerCall.toFixed(2)}</strong>
        <span>{deployment.lastAsk} avUSD per {deployment.quoteSize} CALL</span>
      </div>
      <div className="countdown" aria-label="Time until expiry">
        {countdown.map(({ label, value }) => <div key={label}><strong>{pad(value)}</strong><small>{label}</small></div>)}
      </div>
      <dl className="instrument-stats">
        <div><dt>Spot · TWAP</dt><dd>${deployment.spot.toLocaleString(undefined, { maximumFractionDigits: 2 })}</dd></div>
        <div><dt>Implied vol</dt><dd>{Math.round(deployment.volatility * 100)}%</dd></div>
        <div><dt>Expiry</dt><dd>{expiryLabel}</dd></div>
        <div><dt>Style</dt><dd>European</dd></div>
      </dl>
    </article>
  </section>;
}
