"""Generate exact integer inventory-settlement vectors for AquaVol."""

from __future__ import annotations

import json
from typing import Any, Literal

from .inventory_settlement import WAD, inventory_quote_native


ONE_CALL = 10**18
ONE_CALL_FAIR_QUOTE = 60_294_027
INITIAL_INVENTORY = 10 * ONE_CALL
GAMMA_WAD = 20 * WAD // 100
HALF_SPREAD_WAD = WAD // 100


def _case(
    case_id: str,
    side: Literal["buy", "sell"],
    fair_value_quote: int,
    current_inventory: int,
    quantity: int,
    gamma_wad: int = GAMMA_WAD,
    half_spread_wad: int = HALF_SPREAD_WAD,
) -> dict[str, Any]:
    quote = inventory_quote_native(
        side=side,
        fair_value_quote=fair_value_quote,
        initial_inventory=INITIAL_INVENTORY,
        current_inventory=current_inventory,
        quantity=quantity,
        gamma_wad=gamma_wad,
        half_spread_wad=half_spread_wad,
    )
    return {
        "id": case_id,
        "side": side,
        "inputs": {
            "fair_value_quote": str(fair_value_quote),
            "initial_inventory": str(INITIAL_INVENTORY),
            "current_inventory": str(current_inventory),
            "quantity": str(quantity),
            "gamma_wad": str(gamma_wad),
            "half_spread_wad": str(half_spread_wad),
        },
        "expected": {
            "inventory_after": str(quote.inventory_after),
            "average_exposure_wad": str(quote.average_exposure_wad),
            "inventory_factor_wad": str(quote.inventory_factor_wad),
            "reservation_quote": str(quote.reservation_quote),
            "final_quote": str(quote.final_quote),
        },
    }


def build_document() -> dict[str, Any]:
    cases = [
        _case("first_buy_one", "buy", ONE_CALL_FAIR_QUOTE, 10 * ONE_CALL, ONE_CALL),
        _case("second_buy_one", "buy", ONE_CALL_FAIR_QUOTE, 9 * ONE_CALL, ONE_CALL),
        _case("half_sold_buy_one", "buy", ONE_CALL_FAIR_QUOTE, 5 * ONE_CALL, ONE_CALL),
        _case("half_sold_sell_one", "sell", ONE_CALL_FAIR_QUOTE, 5 * ONE_CALL, ONE_CALL),
        _case(
            "first_buy_five",
            "buy",
            5 * ONE_CALL_FAIR_QUOTE,
            10 * ONE_CALL,
            5 * ONE_CALL,
        ),
        _case(
            "fractional_buy_quarter",
            "buy",
            15_073_507,
            10 * ONE_CALL,
            ONE_CALL // 4,
        ),
        _case("zero_gamma_and_spread", "buy", 1, 10 * ONE_CALL, 1, 0, 0),
        _case(
            "maximum_gamma_and_spread",
            "buy",
            ONE_CALL_FAIR_QUOTE,
            ONE_CALL,
            ONE_CALL,
            WAD,
            WAD // 4,
        ),
    ]
    return {
        "schema": "aquavol.inventory-settlement-vectors",
        "schema_version": 1,
        "numeric_backend": "exact unsigned integer arithmetic",
        "units": {
            "call": "18-decimal token-native units",
            "quote": "6-decimal USDC-native units",
            "factor": "WAD (1e18)",
        },
        "rounding": {
            "buy": "ceiling at inventory and spread stages",
            "sell": "floor at inventory and spread stages",
        },
        "cases": cases,
    }


def main() -> None:
    print(json.dumps(build_document(), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
