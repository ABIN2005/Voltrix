// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { SD59x18, sd } from "@prb/math/src/SD59x18.sol";

/// @notice Bounded standard-normal cumulative distribution approximation.
/// @dev Uses Abramowitz and Stegun, Handbook of Mathematical Functions, formula 26.2.17.
/// Inputs and outputs use 18 decimals. Transcendental math uses unmodified PRBMath
/// v4.2.0 at commit 29a3c06c709496a8f9775dea115935befc5158a7.
library NormalCDF {
    int256 internal constant WAD = 1e18;
    int256 internal constant SATURATION = 8e18;

    // Abramowitz and Stegun 26.2.17 coefficients.
    int256 private constant P = 0.2316419e18;
    int256 private constant B1 = 0.31938153e18;
    int256 private constant B2 = -0.356563782e18;
    int256 private constant B3 = 1.781477937e18;
    int256 private constant B4 = -1.821255978e18;
    int256 private constant B5 = 1.330274429e18;
    int256 private constant INV_SQRT_TWO_PI = 0.398942280401432677e18;

    function cdf(int256 xWad) internal pure returns (uint256 probabilityWad) {
        if (xWad <= -SATURATION) return 0;
        if (xWad >= SATURATION) return uint256(WAD);
        if (xWad == 0) return uint256(WAD / 2);

        bool negative = xWad < 0;
        int256 absoluteRaw = negative ? -xWad : xWad;
        SD59x18 x = sd(absoluteRaw);

        SD59x18 t = sd(WAD) / (sd(WAD) + sd(P) * x);
        SD59x18 polynomial =
        (((((sd(B5) * t + sd(B4)) * t + sd(B3)) * t + sd(B2)) * t + sd(B1)) * t);
        SD59x18 exponent = -(x * x) / sd(2e18);
        SD59x18 density = sd(INV_SQRT_TWO_PI) * exponent.exp();
        int256 positiveResult = WAD - (density * polynomial).unwrap();
        int256 result = negative ? WAD - positiveResult : positiveResult;

        if (result <= 0) return 0;
        if (result >= WAD) return uint256(WAD);
        return uint256(result);
    }
}
