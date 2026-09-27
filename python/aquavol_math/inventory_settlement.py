"""Exact integer inventory settlement shared by vectors and contract tests."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal


WAD = 10**18
MAX_INITIAL_INVENTORY = 2**128 - 1
MAX_GAMMA_WAD = WAD
MAX_HALF_SPREAD_WAD = WAD // 4


@dataclass(frozen=True)
class IntegerInventoryQuote:
    side: Literal["buy", "sell"]
    inventory_after: int
    average_exposure_wad: int
    inventory_factor_wad: int
    reservation_quote: int
    final_quote: int


def _mul_div_up(x: int, y: int, denominator: int) -> int:
    return (x * y + denominator - 1) // denominator


def inventory_quote_native(
    *,
    side: Literal["buy", "sell"],
    fair_value_quote: int,
    initial_inventory: int,
    current_inventory: int,
    quantity: int,
    gamma_wad: int,
    half_spread_wad: int,
) -> IntegerInventoryQuote:
    """Apply the contract's exact two-stage integer settlement rules."""

    if side not in ("buy", "sell"):
        raise ValueError("side must be 'buy' or 'sell'")
    if fair_value_quote <= 0:
        raise ValueError("fair_value_quote must be greater than zero")
    if not 0 < initial_inventory <= MAX_INITIAL_INVENTORY:
        raise ValueError("initial_inventory is outside the uint128 domain")
    if not 0 <= current_inventory <= initial_inventory:
        raise ValueError("current_inventory must be within [0, initial_inventory]")
    if quantity <= 0:
        raise ValueError("quantity must be greater than zero")
    if not 0 <= gamma_wad <= MAX_GAMMA_WAD:
        raise ValueError("gamma_wad must be within [0, 1e18]")
    if not 0 <= half_spread_wad <= MAX_HALF_SPREAD_WAD:
        raise ValueError("half_spread_wad must be within [0, 0.25e18]")

    inventory_after = (
        current_inventory - quantity
        if side == "buy"
        else current_inventory + quantity
    )
    if not 0 <= inventory_after <= initial_inventory:
        raise ValueError("trade would move inventory outside [0, initial_inventory]")

    sold_before = initial_inventory - current_inventory
    sold_after = initial_inventory - inventory_after
    average_exposure_wad = (
        (sold_before + sold_after) * WAD // (2 * initial_inventory)
    )
    inventory_factor_wad = WAD + gamma_wad * average_exposure_wad // WAD

    if side == "buy":
        reservation_quote = _mul_div_up(
            fair_value_quote, inventory_factor_wad, WAD
        )
        final_quote = _mul_div_up(
            reservation_quote, WAD + half_spread_wad, WAD
        )
    else:
        reservation_quote = fair_value_quote * inventory_factor_wad // WAD
        final_quote = reservation_quote * (WAD - half_spread_wad) // WAD

    if final_quote == 0:
        raise ValueError("final_quote must be greater than zero")

    return IntegerInventoryQuote(
        side=side,
        inventory_after=inventory_after,
        average_exposure_wad=average_exposure_wad,
        inventory_factor_wad=inventory_factor_wad,
        reservation_quote=reservation_quote,
        final_quote=final_quote,
    )
