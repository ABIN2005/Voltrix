"""Generate the version-one AquaVol mathematical reference vectors."""

from __future__ import annotations

import json
from decimal import Decimal, ROUND_CEILING, ROUND_FLOOR, ROUND_HALF_EVEN
from typing import Any

from .black_scholes import call_price, inventory_quote, normal_cdf


SECONDS_PER_YEAR = 365 * 24 * 60 * 60
def _decimal(value: float, places: int = 12) -> str:
    return f"{value:.{places}f}"


def _scaled(
    value: float,
    decimals: int = 18,
    source_places: int = 12,
) -> str:
    scale = Decimal(10**decimals)
    return str(
        (Decimal(_decimal(value, source_places)) * scale).to_integral_value(
            rounding=ROUND_HALF_EVEN
        )
    )


def _token_units(value: float, decimals: int, *, round_up: bool) -> str:
    rounding = ROUND_CEILING if round_up else ROUND_FLOOR
    scale = Decimal(10**decimals)
    return str(
        (Decimal(_decimal(value)) * scale).to_integral_value(rounding=rounding)
    )


def _case(
    *,
    case_id: str,
    spot: float,
    strike: float,
    time_seconds: int,
    volatility: float,
) -> dict[str, Any]:
    time_years = time_seconds / SECONDS_PER_YEAR
    result = call_price(
        spot=spot,
        strike=strike,
        time_years=time_years,
        volatility=volatility,
    )

    intermediates = None
    if result.d1 is not None:
        intermediates = {
            "d1": _decimal(result.d1),
            "d2": _decimal(result.d2),
            "cdf_d1": _decimal(result.cdf_d1),
            "cdf_d2": _decimal(result.cdf_d2),
        }

    return {
        "id": case_id,
        "inputs": {
            "spot": _decimal(spot),
            "strike": _decimal(strike),
            "time_seconds": time_seconds,
            "time_years": _decimal(time_years, 18),
            "volatility": _decimal(volatility),
            "risk_free_rate": "0.000000000000",
            "dividend_yield": "0.000000000000",
        },
        "normalized": {
            "spot_wad": _scaled(spot),
            "strike_wad": _scaled(strike),
            "time_wad": _scaled(time_years, source_places=18),
            "volatility_wad": _scaled(volatility),
        },
        "expected": {
            "intrinsic_value": _decimal(result.intrinsic_value),
            "call_value": _decimal(result.call_value),
            "call_value_wad": _scaled(result.call_value),
            "intermediates": intermediates,
        },
    }


def build_document() -> dict[str, Any]:
    seven_days = 7 * 24 * 60 * 60
    cases = [
        _case(
            case_id="canonical_otm_7d_64pct",
            spot=3800.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.64,
        ),
        _case(
            case_id="atm_7d_64pct",
            spot=4000.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.64,
        ),
        _case(
            case_id="itm_7d_64pct",
            spot=4500.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.64,
        ),
        _case(
            case_id="deep_otm_7d_64pct",
            spot=3000.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.64,
        ),
        _case(
            case_id="atm_1h_64pct",
            spot=4000.0,
            strike=4000.0,
            time_seconds=60 * 60,
            volatility=0.64,
        ),
        _case(
            case_id="canonical_1d_64pct",
            spot=3800.0,
            strike=4000.0,
            time_seconds=24 * 60 * 60,
            volatility=0.64,
        ),
        _case(
            case_id="canonical_30d_64pct",
            spot=3800.0,
            strike=4000.0,
            time_seconds=30 * 24 * 60 * 60,
            volatility=0.64,
        ),
        _case(
            case_id="canonical_7d_low_vol",
            spot=3800.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.10,
        ),
        _case(
            case_id="canonical_7d_high_vol",
            spot=3800.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=2.0,
        ),
        _case(
            case_id="expiry_itm",
            spot=4500.0,
            strike=4000.0,
            time_seconds=0,
            volatility=0.64,
        ),
        _case(
            case_id="expiry_otm",
            spot=3800.0,
            strike=4000.0,
            time_seconds=0,
            volatility=0.64,
        ),
        _case(
            case_id="zero_vol_itm",
            spot=4500.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.0,
        ),
        _case(
            case_id="zero_vol_otm",
            spot=3800.0,
            strike=4000.0,
            time_seconds=seven_days,
            volatility=0.0,
        ),
    ]

    canonical_value = float(cases[0]["expected"]["call_value"])
    inventory_cases = []
    for case_id, side, current, quantity in (
        ("first_buy_one", "buy", 10.0, 1.0),
        ("half_sold_buy_one", "buy", 5.0, 1.0),
        ("half_sold_sell_one", "sell", 5.0, 1.0),
        ("first_buy_five", "buy", 10.0, 5.0),
        ("fractional_buy_quarter", "buy", 10.0, 0.25),
    ):
        quote = inventory_quote(
            side=side,
            fair_value=canonical_value,
            initial_inventory=10.0,
            current_inventory=current,
            quantity=quantity,
            gamma=0.20,
            half_spread=0.01,
        )
        inventory_cases.append(
            {
                "id": case_id,
                "side": quote.side,
                "inputs": {
                    "fair_value": _decimal(canonical_value),
                    "initial_inventory": _decimal(10.0),
                    "current_inventory": _decimal(current),
                    "quantity": _decimal(quantity),
                    "gamma": _decimal(0.20),
                    "half_spread": _decimal(0.01),
                },
                "expected": {
                    "inventory_after": _decimal(quote.inventory_after),
                    "exposure_before": _decimal(quote.exposure_before),
                    "exposure_after": _decimal(quote.exposure_after),
                    "average_exposure": _decimal(quote.average_exposure),
                    "reservation_price": _decimal(quote.reservation_price),
                    "unit_premium": _decimal(quote.unit_premium),
                    "total_quote_amount": _decimal(quote.total_quote_amount),
                    "total_quote_usdc_6": _token_units(
                        quote.total_quote_amount,
                        6,
                        round_up=side == "buy",
                    ),
                },
            }
        )

    return {
        "schema": "aquavol.black-scholes-vectors",
        "schema_version": 1,
        "model": {
            "option_type": "european_call",
            "risk_free_rate": "0",
            "dividend_yield": "0",
            "year_seconds": SECONDS_PER_YEAR,
            "normal_cdf": "0.5 * (1 + erf(x / sqrt(2)))",
            "numeric_backend": "Python standard-library binary64",
        },
        "tolerances": {
            "solidity_cdf_max_absolute": "0.000002",
            "solidity_call_absolute_quote": "0.10",
            "solidity_call_relative_bps": "10",
            "settlement_rounding": "maker_favorable_token_native_units",
        },
        "call_cases": cases,
        "cdf_cases": [
            {"x": _decimal(x), "expected": _decimal(normal_cdf(x), 15)}
            for x in (-8.0, -4.0, -1.0, 0.0, 1.0, 4.0, 8.0)
        ],
        "inventory_cases": inventory_cases,
    }


def main() -> None:
    print(json.dumps(build_document(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
