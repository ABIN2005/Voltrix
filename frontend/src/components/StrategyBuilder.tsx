import { useMemo, useState } from "react";
import { deployment } from "../data/deployment";
import { createLeg, modelPremium, type OptionKind, type StrategyLeg } from "../domain/options";
import { PayoffChart } from "./PayoffChart";

const expiries = [
  { value: deployment.liveExpiry, label: "04 Oct 2026", live: true },
  { value: "2026-10-11T03:00:00Z", label: "11 Oct 2026", live: false },
  { value: "2026-10-25T03:00:00Z", label: "25 Oct 2026", live: false },
];
const strikes = [3400, 3600, 3800, 4000, 4200, 4400, 4600];
const liveCall = () => createLeg("CALL", deployment.liveStrike, deployment.liveExpiry);

export function StrategyBuilder() {
  const [expiry, setExpiry] = useState<string>(deployment.liveExpiry);
  const [legs, setLegs] = useState<StrategyLeg[]>([liveCall()]);
  const [notice, setNotice] = useState("");
  const netPremium = useMemo(() => legs.reduce((sum, leg) =>
    sum + (leg.side === "BUY" ? 1 : -1) * leg.premium * leg.quantity, 0), [legs]);

  const replaceInstrument = (id: string, kind: OptionKind, strike: number, nextExpiry: string) => {
    const live = kind === "CALL" && strike === deployment.liveStrike && nextExpiry === deployment.liveExpiry;
    const premium = live ? deployment.lastAsk / deployment.quoteSize : modelPremium(kind, strike, nextExpiry);
    setLegs((all) => all.map((leg) => leg.id === id
      ? { ...leg, kind, strike, expiry: nextExpiry, premium, live } : leg));
  };
  const patchLeg = (id: string, patch: Partial<StrategyLeg>) =>
    setLegs((all) => all.map((leg) => leg.id === id ? { ...leg, ...patch } : leg));
  const addLeg = (leg: StrategyLeg) => {
    if (legs.length === 4) return setNotice("A strategy can contain up to four option legs.");
    setLegs((all) => [...all, leg]); setNotice("");
  };
  const preset = (name: string) => {
    setExpiry(deployment.liveExpiry); setNotice("");
    if (name === "Live call") setLegs([liveCall()]);
    if (name === "Bull call spread") setLegs([
      createLeg("CALL", 4000, deployment.liveExpiry),
      createLeg("CALL", 4400, deployment.liveExpiry, "SELL"),
    ]);
    if (name === "Long straddle") setLegs([
      createLeg("CALL", 4000, deployment.liveExpiry),
      createLeg("PUT", 4000, deployment.liveExpiry),
    ]);
  };
  const quote = (kind: OptionKind, strike: number) => {
    const live = kind === "CALL" && strike === deployment.liveStrike && expiry === deployment.liveExpiry;
    return live ? deployment.lastAsk : modelPremium(kind, strike, expiry) * deployment.quoteSize;
  };

  return <section className="section" id="strategy">
    <div className="section-head">
      <div><span className="eyebrow">Strategy lab</span><h2>Build the position.<br/><span className="gradient-text">Know what's live.</span></h2></div>
      <div className="chip-row" role="group" aria-label="Strategy presets">{["Live call", "Bull call spread", "Long straddle"].map((name) =>
        <button className="chip" key={name} onClick={() => preset(name)}>{name}</button>)}</div>
    </div>
    <div className="builder-grid">
      <article className="panel">
        <div className="panel-heading"><div><span className="eyebrow">Position</span><h3>Strategy legs</h3></div><span className="count-pill">{legs.length}/4 legs</span></div>
        <div className="leg-list">
          {legs.map((leg, index) => <div className="leg-card" key={leg.id}>
            <div className="leg-top">
              <span className="leg-number">0{index + 1}</span>
              <div className="toggle">
                <button className={leg.side === "BUY" ? "buy-active" : ""} onClick={() => patchLeg(leg.id, { side: "BUY" })}>BUY</button>
                <button className={leg.side === "SELL" ? "sell-active" : ""} onClick={() => patchLeg(leg.id, { side: "SELL" })}>SELL</button>
              </div>
              <div className="toggle">{(["CALL", "PUT"] as OptionKind[]).map((kind) =>
                <button className={leg.kind === kind ? "type-active" : ""} key={kind} onClick={() => replaceInstrument(leg.id, kind, leg.strike, leg.expiry)}>{kind}</button>)}</div>
              <span className={leg.live ? "live-badge" : "sim-badge"}>{leg.live ? "LIVE" : "SIM"}</span>
              <button className="remove" aria-label={`Remove leg ${index + 1}`} onClick={() => setLegs((all) => all.filter((item) => item.id !== leg.id))}>×</button>
            </div>
            <div className="leg-fields">
              <label>Expiry<select value={leg.expiry} onChange={(e) => replaceInstrument(leg.id, leg.kind, leg.strike, e.target.value)}>
                {expiries.map((item) => <option key={item.value} value={item.value}>{item.label}</option>)}</select></label>
              <label>Strike<input type="number" step="100" value={leg.strike} onChange={(e) => replaceInstrument(leg.id, leg.kind, Number(e.target.value), leg.expiry)}/></label>
              <label>Quantity<input type="number" min=".01" step=".01" value={leg.quantity} onChange={(e) => patchLeg(leg.id, { quantity: Math.max(Number(e.target.value), .01) })}/></label>
              <label>Premium<input type="number" min="0" step=".01" value={leg.premium.toFixed(2)} onChange={(e) => patchLeg(leg.id, { premium: Math.max(Number(e.target.value), 0) })}/></label>
            </div>
          </div>)}
          {!legs.length && <div className="empty">Select an option from the ladder to begin.</div>}
        </div>
        {notice && <p className="notice">{notice}</p>}
        <div className="summary">
          <div><small>Net premium</small><strong>${Math.abs(netPremium).toFixed(2)}</strong><span>{netPremium >= 0 ? "Debit" : "Credit"}</span></div>
          <div><small>Live legs</small><strong>{legs.filter((leg) => leg.live).length}</strong><span>of {legs.length}</span></div>
          <div><small>Settlement</small><strong>{legs.length === 1 && legs[0].live ? "On-chain" : "Simulated"}</strong><span>Status</span></div>
        </div>
      </article>
      <article className="panel">
        <div className="panel-heading"><div><span className="eyebrow">Options surface</span><h3>Strike ladder</h3></div>
          <select value={expiry} onChange={(e) => setExpiry(e.target.value)}>{expiries.map((item) =>
            <option key={item.value} value={item.value}>{item.label} · {item.live ? "LIVE" : "SIM"}</option>)}</select></div>
        <div className="ladder-head"><span>Call ask / 0.01</span><span>Strike</span><span>Put ask / 0.01</span></div>
        {strikes.map((strike) => {
          const live = strike === deployment.liveStrike && expiry === deployment.liveExpiry;
          return <div className={`ladder-row ${Math.abs(strike - deployment.spot) <= 200 ? "near" : ""}`} key={strike}>
            <button className="quote" onClick={() => addLeg(createLeg("CALL", strike, expiry))}><strong>{quote("CALL", strike).toFixed(3)}</strong><small>+ CALL</small></button>
            <div className="strike"><strong>${strike.toLocaleString()}</strong><span className={live ? "live-badge" : "sim-badge"}>{live ? "LIVE" : "SIM"}</span></div>
            <button className="quote put" onClick={() => addLeg(createLeg("PUT", strike, expiry))}><strong>{quote("PUT", strike).toFixed(3)}</strong><small>+ PUT</small></button>
          </div>;
        })}
        <p className="panel-note">Only the $4,000 CALL expiring 04 Oct is deployed. All other quotes are simulations.</p>
      </article>
    </div>
    <PayoffChart legs={legs} />
  </section>;
}
