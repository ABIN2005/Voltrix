import { useMemo, useState, type PointerEvent } from "react";
import { deployment } from "../data/deployment";
import { strategyPayoff, type StrategyLeg } from "../domain/options";

interface Props { legs: StrategyLeg[] }
const cash = (value: number) => `${value < 0 ? "−" : ""}$${Math.abs(value).toFixed(2)}`;

export function PayoffChart({ legs }: Props) {
  const [hover, setHover] = useState<number | null>(null);
  const width = 1000, height = 400;
  const margin = { top: 34, right: 30, bottom: 48, left: 68 };
  const points = useMemo(() => {
    const legStrikes = legs.map((leg) => leg.strike);
    const low = Math.min(deployment.spot * .7, ...legStrikes.map((strike) => strike * .8));
    const high = Math.max(deployment.spot * 1.3, ...legStrikes.map((strike) => strike * 1.2));
    return Array.from({ length: 161 }, (_, index) => {
      const spot = low + index / 160 * (high - low);
      return { spot, payoff: strategyPayoff(legs, spot) };
    });
  }, [legs]);
  const metrics = useMemo(() => {
    const values = points.map((point) => point.payoff);
    const crossings: number[] = [];
    for (let index = 1; index < points.length; index++) {
      if (values[index] === 0 || values[index] * values[index - 1] < 0) crossings.push(points[index].spot);
    }
    return { max: Math.max(...values), min: Math.min(...values), breakEvens: crossings.slice(0, 2) };
  }, [points]);
  const minX = points[0].spot, maxX = points[points.length - 1].spot;
  const extent = Math.max(Math.abs(metrics.min), Math.abs(metrics.max), 1) * 1.18;
  const x = (value: number) => margin.left + (value - minX) / (maxX - minX) * (width - margin.left - margin.right);
  const y = (value: number) => margin.top + (extent - value) / (extent * 2) * (height - margin.top - margin.bottom);
  const line = points.map((point, index) => `${index ? "L" : "M"}${x(point.spot)},${y(point.payoff)}`).join(" ");
  const area = `${line} L${x(maxX)},${y(0)} L${x(minX)},${y(0)} Z`;
  const selected = hover === null ? null : points[hover];
  const strikes = [...new Set(legs.map((leg) => leg.strike))];
  const move = (event: PointerEvent<SVGSVGElement>) => {
    const rect = event.currentTarget.getBoundingClientRect();
    const cursor = (event.clientX - rect.left) / rect.width * width;
    const ratio = Math.max(0, Math.min(1, (cursor - margin.left) / (width - margin.left - margin.right)));
    setHover(Math.round(ratio * (points.length - 1)));
  };

  return <article className="panel payoff-panel">
    <div className="panel-heading payoff-heading">
      <div><span className="eyebrow">Expiry P&amp;L</span><h3>Multi-leg payoff</h3></div>
      <div className="chart-legend"><span><i className="profit-key"/>Profit</span><span><i className="loss-key"/>Loss</span></div>
    </div>
    <div className="payoff-metrics">
      <div><small>Breakeven</small><strong>{metrics.breakEvens.length ? metrics.breakEvens.map((value) => `$${value.toFixed(0)}`).join(" · ") : "—"}</strong></div>
      <div><small>Window max</small><strong className="gain">{cash(metrics.max)}</strong></div>
      <div><small>Window min</small><strong className="loss">{cash(metrics.min)}</strong></div>
      <div><small>Live TWAP</small><strong>${deployment.spot.toFixed(2)}</strong></div>
    </div>
    <div className="chart-wrap">
      <svg viewBox={`0 0 ${width} ${height}`} onPointerMove={move} onPointerLeave={() => setHover(null)}>
        <defs>
          <linearGradient id="gain-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#34f5a4" stopOpacity=".3"/><stop offset="1" stopColor="#34f5a4" stopOpacity="0"/></linearGradient>
          <linearGradient id="loss-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ff5c8a" stopOpacity="0"/><stop offset="1" stopColor="#ff5c8a" stopOpacity=".28"/></linearGradient>
          <clipPath id="gain-clip"><rect width={width} height={y(0)}/></clipPath>
          <clipPath id="loss-clip"><rect y={y(0)} width={width} height={height - y(0)}/></clipPath>
        </defs>
        {[.25,.5,.75].map((ratio) => <line className="chart-grid" key={ratio} x1={margin.left} x2={width-margin.right} y1={margin.top+ratio*(height-margin.top-margin.bottom)} y2={margin.top+ratio*(height-margin.top-margin.bottom)}/>)}
        <line className="zero-axis" x1={margin.left} x2={width-margin.right} y1={y(0)} y2={y(0)}/>
        <path d={area} fill="url(#gain-fill)" clipPath="url(#gain-clip)"/><path d={area} fill="url(#loss-fill)" clipPath="url(#loss-clip)"/>
        <path d={line} className="payoff-line gain-line" clipPath="url(#gain-clip)"/><path d={line} className="payoff-line loss-line" clipPath="url(#loss-clip)"/>
        {strikes.map((strike) => <g key={strike}><line className="strike-marker" x1={x(strike)} x2={x(strike)} y1={margin.top} y2={height-margin.bottom}/><text className="strike-label" x={x(strike)+5} y={height-margin.bottom-7}>K {strike}</text></g>)}
        <line className="spot-marker" x1={x(deployment.spot)} x2={x(deployment.spot)} y1={margin.top} y2={height-margin.bottom}/>
        <text className="spot-label" x={x(deployment.spot)+6} y={margin.top+12}>TWAP</text>
        {[minX,(minX+maxX)/2,maxX].map((tick) => <text className="axis-text" key={tick} x={x(tick)} y={height-16} textAnchor="middle">${tick.toFixed(0)}</text>)}
        <text className="axis-text" x={margin.left-10} y={y(extent)+4} textAnchor="end">{cash(extent)}</text><text className="axis-text" x={margin.left-10} y={y(0)+4} textAnchor="end">$0</text><text className="axis-text" x={margin.left-10} y={y(-extent)+4} textAnchor="end">{cash(-extent)}</text>
        {selected && <g>
          <line className="crosshair" x1={x(selected.spot)} x2={x(selected.spot)} y1={margin.top} y2={height-margin.bottom}/>
          <circle className={selected.payoff >= 0 ? "gain-dot" : "loss-dot"} cx={x(selected.spot)} cy={y(selected.payoff)} r="5"/>
          <g transform={`translate(${Math.min(x(selected.spot)+12,width-190)},${Math.max(y(selected.payoff)-57,12)})`}>
            <rect className="tooltip-box" width="174" height="50" rx="8"/><text className="tooltip-title" x="12" y="20">WETH ${selected.spot.toFixed(0)}</text><text className={selected.payoff >= 0 ? "tooltip-gain" : "tooltip-loss"} x="12" y="39">P&amp;L {cash(selected.payoff)}</text>
          </g>
        </g>}
      </svg>
    </div>
    <div className="chart-footer"><span>← WETH downside</span><strong>WETH price at expiry</strong><span>WETH upside →</span></div>
  </article>;
}
