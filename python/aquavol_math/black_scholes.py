"""Reference Black-Scholes and inventory pricing for AquaVol.

The reference intentionally uses ordinary Python floating-point arithmetic and
``math.erf``. It is independent from the future fixed-point Solidity
implementation and exists to generate test vectors, not executable quotes.
"""

from __future__ import annotations

from dataclasses import dataclass
from math import erf, exp, isfinite, log, sqrt
from typing import Literal


SQRT_TWO = sqrt(2.0)
MAX_PRICE = 1_000_000.0
MAX_TIME_YEARS = 366 / 365
MAX_VOLATILITY = 5.0
MAX_HALF_SPREAD = 0.25


@dataclass(frozen=True)
class BlackScholesResult:
    """Intermediate and final values for one European call calculation."""

    intrinsic_value: float
    call_value: float
    d1: float | None
    d2: float | None
    cdf_d1: float | None
    cdf_d2: float | None


@dataclass(frozen=True)
class InventoryQuote:
    """Inventory transition and executable unit premium for one trade."""

    side: Literal["buy", "sell"]
    inventory_before: float
    inventory_after: float
    exposure_before: float
    exposure_after: float
    average_exposure: float
    reservation_price: float
    unit_premium: float
    total_quote_amount: float


def _require_finite(name: str, value: float) -> None:
    if not isfinite(value):
        raise ValueError(f"{name} must be finite")


def normal_cdf(x: float) -> float:
    """Return the standard normal cumulative distribution at ``x``."""

    _require_finite("x", x)
    return 0.5 * (1.0 + erf(x / SQRT_TWO))


def call_price(
    *,
    spot: float,
    strike: float,
    time_years: float,
    volatility: float,
    risk_free_rate: float = 0.0,
    dividend_yield: float = 0.0,
) -> BlackScholesResult:
    """Price a European call and expose its reference intermediates.

    AquaVol fixes ``risk_free_rate`` and ``dividend_yield`` to zero for the MVP.
    They remain explicit here so tests can reject an accidental model change.
    """

    values = {
        "spot": spot,
        "strike": strike,
        "time_years": time_years,
        "volatility": volatility,
        "risk_free_rate": risk_free_rate,
        "dividend_yield": dividend_yield,
    }
    for name, value in values.items():
        _require_finite(name, value)

    if spot <= 0.0:
        raise ValueError("spot must be greater than zero")
    if spot > MAX_PRICE:
        raise ValueError("spot exceeds the supported domain")
    if strike <= 0.0:
        raise ValueError("strike must be greater than zero")
    if strike > MAX_PRICE:
        raise ValueError("strike exceeds the supported domain")
    if time_years < 0.0:
        raise ValueError("time_years must not be negative")
    if time_years > MAX_TIME_YEARS:
        raise ValueError("time_years exceeds the supported domain")
    if volatility < 0.0:
        raise ValueError("volatility must not be negative")
    if volatility > MAX_VOLATILITY:
        raise ValueError("volatility exceeds the supported domain")
    if risk_free_rate != 0.0:
        raise ValueError("AquaVol MVP requires a zero risk-free rate")
    if dividend_yield != 0.0:
        raise ValueError("AquaVol MVP requires a zero dividend yield")

    intrinsic = max(spot - strike, 0.0)
    if time_years == 0.0 or volatility == 0.0:
        return BlackScholesResult(
            intrinsic_value=intrinsic,
            call_value=intrinsic,
            d1=None,
            d2=None,
            cdf_d1=None,
            cdf_d2=None,
        )

    sqrt_time = sqrt(time_years)
    sigma_sqrt_time = volatility * sqrt_time
    d1 = (
        log(spot / strike)
        + (risk_free_rate - dividend_yield + 0.5 * volatility**2) * time_years
    ) / sigma_sqrt_time
    d2 = d1 - sigma_sqrt_time
    cdf_d1 = normal_cdf(d1)
    cdf_d2 = normal_cdf(d2)

    discounted_spot = spot * exp(-dividend_yield * time_years)
    discounted_strike = strike * exp(-risk_free_rate * time_years)
    value = discounted_spot * cdf_d1 - discounted_strike * cdf_d2

    # Preserve the analytical zero-rate call bounds against tiny float noise.
    value = min(max(value, intrinsic), spot)

    return BlackScholesResult(
        intrinsic_value=intrinsic,
        call_value=value,
        d1=d1,
        d2=d2,
        cdf_d1=cdf_d1,
        cdf_d2=cdf_d2,
    )


def inventory_quote(
    *,
    side: Literal["buy", "sell"],
    fair_value: float,
    initial_inventory: float,
    current_inventory: float,
    quantity: float,
    gamma: float,
    half_spread: float,
) -> InventoryQuote:
    """Apply the specified linear inventory curve to a CALL trade."""

    values = {
        "fair_value": fair_value,
        "initial_inventory": initial_inventory,
        "current_inventory": current_inventory,
        "quantity": quantity,
        "gamma": gamma,
        "half_spread": half_spread,
    }
    for name, value in values.items():
        _require_finite(name, value)

    if side not in ("buy", "sell"):
        raise ValueError("side must be 'buy' or 'sell'")
    if fair_value < 0.0:
        raise ValueError("fair_value must not be negative")
    if initial_inventory <= 0.0:
        raise ValueError("initial_inventory must be greater than zero")
    if not 0.0 <= current_inventory <= initial_inventory:
        raise ValueError("current_inventory must be within [0, initial_inventory]")
    if quantity <= 0.0:
        raise ValueError("quantity must be greater than zero")
    if not 0.0 <= gamma <= 1.0:
        raise ValueError("gamma must be within [0, 1]")
    if not 0.0 <= half_spread <= MAX_HALF_SPREAD:
        raise ValueError("half_spread must be within [0, 0.25]")

    inventory_after = (
        current_inventory - quantity
        if side == "buy"
        else current_inventory + quantity
    )
    if not 0.0 <= inventory_after <= initial_inventory:
        raise ValueError("trade would move inventory outside [0, initial_inventory]")

    exposure_before = (initial_inventory - current_inventory) / initial_inventory
    exposure_after = (initial_inventory - inventory_after) / initial_inventory
    average_exposure = (exposure_before + exposure_after) / 2.0
    reservation_price = fair_value * (1.0 + gamma * average_exposure)
    spread_multiplier = 1.0 + half_spread if side == "buy" else 1.0 - half_spread
    unit_premium = reservation_price * spread_multiplier

    return InventoryQuote(
        side=side,
        inventory_before=current_inventory,
        inventory_after=inventory_after,
        exposure_before=exposure_before,
        exposure_after=exposure_after,
        average_exposure=average_exposure,
        reservation_price=reservation_price,
        unit_premium=unit_premium,
        total_quote_amount=unit_premium * quantity,
    )
