import { deployment } from "../data/deployment";

export type OptionKind = "CALL" | "PUT";
export type PositionSide = "BUY" | "SELL";

export interface StrategyLeg {
  id: string;
  kind: OptionKind;
  side: PositionSide;
  strike: number;
  expiry: string;
  quantity: number;
  premium: number;
  live: boolean;
}

const normalCdf = (x: number) => {
  const sign = x < 0 ? -1 : 1;
  const z = Math.abs(x) / Math.sqrt(2);
  const t = 1 / (1 + 0.3275911 * z);
  const erf =
    1 -
    (((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t -
      0.284496736) *
      t +
      0.254829592) *
      t) *
      Math.exp(-z * z);
  return 0.5 * (1 + sign * erf);
};

export const yearsToExpiry = (expiry: string) =>
  Math.max(
    (new Date(expiry).getTime() - Date.now()) / 31_536_000_000,
    1 / 365 / 24,
  );

export const blackScholes = (
  kind: OptionKind,
  spot: number,
  strike: number,
  volatility: number,
  time: number,
) => {
  const sigmaRootT = volatility * Math.sqrt(time);
  const d1 =
    (Math.log(spot / strike) + 0.5 * volatility * volatility * time) /
    sigmaRootT;
  const d2 = d1 - sigmaRootT;
  if (kind === "CALL") {
    return spot * normalCdf(d1) - strike * normalCdf(d2);
  }
  return strike * normalCdf(-d2) - spot * normalCdf(-d1);
};

export const modelPremium = (
  kind: OptionKind,
  strike: number,
  expiry: string,
) =>
  blackScholes(
    kind,
    deployment.spot,
    strike,
    deployment.volatility,
    yearsToExpiry(expiry),
  );

export const legPayoff = (leg: StrategyLeg, terminalSpot: number) => {
  const intrinsic =
    leg.kind === "CALL"
      ? Math.max(terminalSpot - leg.strike, 0)
      : Math.max(leg.strike - terminalSpot, 0);
  const longPayoff = (intrinsic - leg.premium) * leg.quantity;
  return leg.side === "BUY" ? longPayoff : -longPayoff;
};

export const strategyPayoff = (
  legs: StrategyLeg[],
  terminalSpot: number,
) => legs.reduce((total, leg) => total + legPayoff(leg, terminalSpot), 0);

export const createLeg = (
  kind: OptionKind,
  strike: number,
  expiry: string,
  side: PositionSide = "BUY",
): StrategyLeg => {
  const live =
    kind === "CALL" &&
    strike === deployment.liveStrike &&
    expiry === deployment.liveExpiry;
  return {
    id: crypto.randomUUID(),
    kind,
    side,
    strike,
    expiry,
    quantity: deployment.quoteSize,
    premium: live
      ? deployment.lastAsk / deployment.quoteSize
      : modelPremium(kind, strike, expiry),
    live,
  };
};
