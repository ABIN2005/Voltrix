from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

from aquavol_math.black_scholes import call_price, inventory_quote, normal_cdf
from aquavol_math.generate_vectors import build_document


class NormalCDFTests(unittest.TestCase):
    def test_known_values(self) -> None:
        self.assertAlmostEqual(normal_cdf(0.0), 0.5, places=15)
        self.assertAlmostEqual(normal_cdf(1.0), 0.8413447460685429, places=15)
        self.assertAlmostEqual(normal_cdf(-1.0), 0.15865525393145707, places=15)

    def test_symmetry_and_monotonicity(self) -> None:
        points = [index / 10 for index in range(-80, 81)]
        values = [normal_cdf(point) for point in points]
        self.assertEqual(values, sorted(values))
        for point in (0.25, 1.0, 2.5, 4.0, 8.0):
            self.assertAlmostEqual(normal_cdf(-point), 1.0 - normal_cdf(point))

    def test_non_finite_value_is_rejected(self) -> None:
        for value in (math.inf, -math.inf, math.nan):
            with self.subTest(value=value), self.assertRaises(ValueError):
                normal_cdf(value)

    def test_solidity_approximation_error_budget(self) -> None:
        def approximation(x: float) -> float:
            if x <= -8.0:
                return 0.0
            if x >= 8.0:
                return 1.0
            if x == 0.0:
                return 0.5

            absolute = abs(x)
            t = 1.0 / (1.0 + 0.2316419 * absolute)
            polynomial = (
                0.319381530 * t
                - 0.356563782 * t**2
                + 1.781477937 * t**3
                - 1.821255978 * t**4
                + 1.330274429 * t**5
            )
            density = math.exp(-(absolute**2) / 2.0) / math.sqrt(2.0 * math.pi)
            positive = 1.0 - density * polynomial
            return 1.0 - positive if x < 0.0 else positive

        points = [index / 100 for index in range(-800, 801)]
        errors = [abs(approximation(point) - normal_cdf(point)) for point in points]
        self.assertLessEqual(max(errors), 0.000002)


class BlackScholesTests(unittest.TestCase):
    def test_canonical_call_value(self) -> None:
        result = call_price(
            spot=3800.0,
            strike=4000.0,
            time_years=7 / 365,
            volatility=0.64,
        )
        self.assertAlmostEqual(result.call_value, 60.29, delta=0.10)
        self.assertGreaterEqual(result.call_value, result.intrinsic_value)
        self.assertLessEqual(result.call_value, 3800.0)

    def test_expiry_and_zero_volatility_return_intrinsic_value(self) -> None:
        expiry = call_price(
            spot=4500.0,
            strike=4000.0,
            time_years=0.0,
            volatility=0.64,
        )
        zero_volatility = call_price(
            spot=4500.0,
            strike=4000.0,
            time_years=7 / 365,
            volatility=0.0,
        )
        self.assertEqual(expiry.call_value, 500.0)
        self.assertEqual(zero_volatility.call_value, 500.0)
        self.assertIsNone(expiry.d1)
        self.assertIsNone(zero_volatility.d1)

    def test_invalid_inputs_are_rejected(self) -> None:
        baseline = {
            "spot": 3800.0,
            "strike": 4000.0,
            "time_years": 7 / 365,
            "volatility": 0.64,
        }
        for field, value in (
            ("spot", 0.0),
            ("spot", 1_000_000.01),
            ("strike", 0.0),
            ("strike", 1_000_000.01),
            ("time_years", -1.0),
            ("time_years", 367 / 365),
            ("volatility", -0.1),
            ("volatility", 5.01),
        ):
            inputs = baseline | {field: value}
            with self.subTest(field=field), self.assertRaises(ValueError):
                call_price(**inputs)

        with self.assertRaises(ValueError):
            call_price(**baseline, risk_free_rate=0.01)
        with self.assertRaises(ValueError):
            call_price(**baseline, dividend_yield=0.01)


class InventoryQuoteTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fair_value = call_price(
            spot=3800.0,
            strike=4000.0,
            time_years=7 / 365,
            volatility=0.64,
        ).call_value

    def test_first_purchase_includes_average_inventory_risk(self) -> None:
        quote = inventory_quote(
            side="buy",
            fair_value=self.fair_value,
            initial_inventory=10.0,
            current_inventory=10.0,
            quantity=1.0,
            gamma=0.20,
            half_spread=0.01,
        )
        self.assertEqual(quote.inventory_after, 9.0)
        self.assertAlmostEqual(quote.average_exposure, 0.05)
        self.assertGreater(quote.unit_premium, self.fair_value)

    def test_buying_five_matches_five_sequential_unit_buys(self) -> None:
        block = inventory_quote(
            side="buy",
            fair_value=self.fair_value,
            initial_inventory=10.0,
            current_inventory=10.0,
            quantity=5.0,
            gamma=0.20,
            half_spread=0.01,
        )
        sequential_total = 0.0
        current = 10.0
        for _ in range(5):
            quote = inventory_quote(
                side="buy",
                fair_value=self.fair_value,
                initial_inventory=10.0,
                current_inventory=current,
                quantity=1.0,
                gamma=0.20,
                half_spread=0.01,
            )
            sequential_total += quote.total_quote_amount
            current = quote.inventory_after
        self.assertAlmostEqual(block.total_quote_amount, sequential_total, places=10)

    def test_sellback_cannot_exceed_initial_inventory(self) -> None:
        with self.assertRaises(ValueError):
            inventory_quote(
                side="sell",
                fair_value=self.fair_value,
                initial_inventory=10.0,
                current_inventory=10.0,
                quantity=1.0,
                gamma=0.20,
                half_spread=0.01,
            )

    def test_excessive_spread_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            inventory_quote(
                side="buy",
                fair_value=self.fair_value,
                initial_inventory=10.0,
                current_inventory=10.0,
                quantity=1.0,
                gamma=0.20,
                half_spread=0.251,
            )


class VectorDocumentTests(unittest.TestCase):
    def test_committed_document_matches_generator(self) -> None:
        repository_root = Path(__file__).resolve().parents[2]
        vector_path = repository_root / "test" / "vectors" / "black_scholes-v1.json"
        committed = json.loads(vector_path.read_text(encoding="utf-8"))
        self.assertEqual(committed, build_document())


if __name__ == "__main__":
    unittest.main()
