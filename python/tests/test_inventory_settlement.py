from __future__ import annotations

import json
import unittest
from pathlib import Path

from aquavol_math.generate_inventory_vectors import (
    GAMMA_WAD,
    HALF_SPREAD_WAD,
    INITIAL_INVENTORY,
    ONE_CALL,
    ONE_CALL_FAIR_QUOTE,
    build_document,
)
from aquavol_math.inventory_settlement import (
    MAX_INITIAL_INVENTORY,
    WAD,
    inventory_quote_native,
)


class IntegerInventorySettlementTests(unittest.TestCase):
    def test_canonical_first_buy_matches_architecture_example(self) -> None:
        quote = inventory_quote_native(
            side="buy",
            fair_value_quote=ONE_CALL_FAIR_QUOTE,
            initial_inventory=INITIAL_INVENTORY,
            current_inventory=INITIAL_INVENTORY,
            quantity=ONE_CALL,
            gamma_wad=GAMMA_WAD,
            half_spread_wad=HALF_SPREAD_WAD,
        )
        self.assertEqual(quote.average_exposure_wad, 5 * WAD // 100)
        self.assertEqual(quote.inventory_factor_wad, 101 * WAD // 100)
        self.assertEqual(quote.reservation_quote, 60_896_968)
        self.assertEqual(quote.final_quote, 61_505_938)

    def test_later_identical_buy_is_more_expensive(self) -> None:
        first = self._canonical_buy(INITIAL_INVENTORY)
        second = self._canonical_buy(INITIAL_INVENTORY - ONE_CALL)
        self.assertGreater(second.final_quote, first.final_quote)

    def test_block_and_sequential_buys_stay_inside_rounding_budget(self) -> None:
        block = inventory_quote_native(
            side="buy",
            fair_value_quote=5 * ONE_CALL_FAIR_QUOTE,
            initial_inventory=INITIAL_INVENTORY,
            current_inventory=INITIAL_INVENTORY,
            quantity=5 * ONE_CALL,
            gamma_wad=GAMMA_WAD,
            half_spread_wad=HALF_SPREAD_WAD,
        )
        current = INITIAL_INVENTORY
        sequential_total = 0
        for _ in range(5):
            quote = self._canonical_buy(current)
            sequential_total += quote.final_quote
            current = quote.inventory_after
        self.assertLessEqual(abs(block.final_quote - sequential_total), 3 * (5 + 1))

    def test_accepted_boundaries(self) -> None:
        minimum = inventory_quote_native(
            side="buy",
            fair_value_quote=1,
            initial_inventory=1,
            current_inventory=1,
            quantity=1,
            gamma_wad=0,
            half_spread_wad=0,
        )
        self.assertEqual(minimum.final_quote, 1)

        maximum = inventory_quote_native(
            side="sell",
            fair_value_quote=2,
            initial_inventory=MAX_INITIAL_INVENTORY,
            current_inventory=0,
            quantity=MAX_INITIAL_INVENTORY,
            gamma_wad=WAD,
            half_spread_wad=WAD // 4,
        )
        self.assertGreater(maximum.final_quote, 0)

    def test_rejected_boundaries(self) -> None:
        baseline = {
            "side": "buy",
            "fair_value_quote": ONE_CALL_FAIR_QUOTE,
            "initial_inventory": INITIAL_INVENTORY,
            "current_inventory": INITIAL_INVENTORY,
            "quantity": ONE_CALL,
            "gamma_wad": GAMMA_WAD,
            "half_spread_wad": HALF_SPREAD_WAD,
        }
        for field, value in (
            ("fair_value_quote", 0),
            ("initial_inventory", 0),
            ("initial_inventory", MAX_INITIAL_INVENTORY + 1),
            ("current_inventory", INITIAL_INVENTORY + 1),
            ("quantity", 0),
            ("quantity", INITIAL_INVENTORY + 1),
            ("gamma_wad", WAD + 1),
            ("half_spread_wad", WAD // 4 + 1),
        ):
            with self.subTest(field=field), self.assertRaises(ValueError):
                inventory_quote_native(**(baseline | {field: value}))

    def test_sell_that_rounds_to_zero_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            inventory_quote_native(
                side="sell",
                fair_value_quote=1,
                initial_inventory=2,
                current_inventory=1,
                quantity=1,
                gamma_wad=0,
                half_spread_wad=WAD // 4,
            )

    def test_committed_document_matches_generator(self) -> None:
        repository_root = Path(__file__).resolve().parents[2]
        vector_path = repository_root / "test" / "vectors" / "inventory_settlement-v1.json"
        committed = json.loads(vector_path.read_text(encoding="utf-8"))
        self.assertEqual(committed, build_document())

    def _canonical_buy(self, current_inventory: int):
        return inventory_quote_native(
            side="buy",
            fair_value_quote=ONE_CALL_FAIR_QUOTE,
            initial_inventory=INITIAL_INVENTORY,
            current_inventory=current_inventory,
            quantity=ONE_CALL,
            gamma_wad=GAMMA_WAD,
            half_spread_wad=HALF_SPREAD_WAD,
        )


if __name__ == "__main__":
    unittest.main()
