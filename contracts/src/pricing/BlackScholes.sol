// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { SD59x18, sd } from "@prb/math/src/SD59x18.sol";

import { FullMath } from "../libraries/FullMath.sol";
import { NormalCDF } from "./NormalCDF.sol";

/// @notice Bounded zero-rate, zero-dividend European-call pricing for AquaVol.
/// @dev Transcendental math uses unmodified PRBMath v4.2.0 at commit
/// 29a3c06c709496a8f9775dea115935befc5158a7.
library BlackScholes {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant YEAR_SECONDS = 365 days;
    uint256 internal constant MAX_TIME_SECONDS = 366 days;
    uint256 internal constant MAX_PRICE_WAD = 1_000_000e18;
    uint256 internal constant MIN_VOLATILITY_WAD = 0.0001e18;
    uint256 internal constant MAX_VOLATILITY_WAD = 5e18;
    uint256 internal constant CDF_MAX_ERROR_WAD = 0.000002e18;

    struct Result {
        uint256 premiumWad;
        int256 d1Wad;
        int256 d2Wad;
        uint256 cdfD1Wad;
        uint256 cdfD2Wad;
    }

    error SpotOutsideDomain(uint256 spotWad);
    error StrikeOutsideDomain(uint256 strikeWad);
    error TimeOutsideDomain(uint256 timeSeconds);
    error VolatilityOutsideDomain(uint256 volatilityWad);
    error FairValueOutsideBounds(uint256 premiumWad, uint256 intrinsicWad, uint256 spotWad);
    error NegativeFairValueComponents(uint256 spotComponentWad, uint256 strikeComponentWad);

    function callPrice(
        uint256 spotWad,
        uint256 strikeWad,
        uint256 timeSeconds,
        uint256 volatilityWad
    ) internal pure returns (uint256 premiumWad) {
        return calculate(spotWad, strikeWad, timeSeconds, volatilityWad).premiumWad;
    }

    function calculate(
        uint256 spotWad,
        uint256 strikeWad,
        uint256 timeSeconds,
        uint256 volatilityWad
    ) internal pure returns (Result memory result) {
        _validateInputs(spotWad, strikeWad, timeSeconds, volatilityWad);

        uint256 intrinsicWad = spotWad > strikeWad ? spotWad - strikeWad : 0;
        if (timeSeconds == 0 || volatilityWad == 0) {
            result.premiumWad = intrinsicWad;
            return result;
        }

        uint256 timeWad = FullMath.mulDiv(timeSeconds, WAD, YEAR_SECONDS);
        SD59x18 time = sd(int256(timeWad));
        SD59x18 sigma = sd(int256(volatilityWad));
        SD59x18 sigmaSquared = sigma * sigma;
        SD59x18 sigmaSqrtTime = sigma * time.sqrt();
        SD59x18 logMoneyness = sd(int256(spotWad)).ln() - sd(int256(strikeWad)).ln();
        SD59x18 varianceTerm = (sigmaSquared * time) / sd(2e18);
        SD59x18 d1 = (logMoneyness + varianceTerm) / sigmaSqrtTime;
        SD59x18 d2 = d1 - sigmaSqrtTime;

        result.d1Wad = d1.unwrap();
        result.d2Wad = d2.unwrap();
        result.cdfD1Wad = NormalCDF.cdf(result.d1Wad);
        result.cdfD2Wad = NormalCDF.cdf(result.d2Wad);

        uint256 spotComponentWad = FullMath.mulDiv(spotWad, result.cdfD1Wad, WAD);
        uint256 strikeComponentWad = FullMath.mulDiv(strikeWad, result.cdfD2Wad, WAD);
        uint256 maximumApproximationErrorWad =
            FullMath.mulDiv(spotWad + strikeWad, CDF_MAX_ERROR_WAD, WAD) + 2;
        if (spotComponentWad < strikeComponentWad) {
            uint256 gapToLowerBound = intrinsicWad + (strikeComponentWad - spotComponentWad);
            if (gapToLowerBound <= maximumApproximationErrorWad) {
                result.premiumWad = intrinsicWad;
                return result;
            }
            revert NegativeFairValueComponents(spotComponentWad, strikeComponentWad);
        }

        result.premiumWad = spotComponentWad - strikeComponentWad;
        if (result.premiumWad < intrinsicWad) {
            if (intrinsicWad - result.premiumWad <= maximumApproximationErrorWad) {
                result.premiumWad = intrinsicWad;
                return result;
            }
            revert FairValueOutsideBounds(result.premiumWad, intrinsicWad, spotWad);
        }
        if (result.premiumWad > spotWad) {
            if (result.premiumWad - spotWad <= maximumApproximationErrorWad) {
                result.premiumWad = spotWad;
                return result;
            }
            revert FairValueOutsideBounds(result.premiumWad, intrinsicWad, spotWad);
        }
    }

    function _validateInputs(
        uint256 spotWad,
        uint256 strikeWad,
        uint256 timeSeconds,
        uint256 volatilityWad
    ) private pure {
        if (spotWad == 0 || spotWad > MAX_PRICE_WAD) {
            revert SpotOutsideDomain(spotWad);
        }
        if (strikeWad == 0 || strikeWad > MAX_PRICE_WAD) {
            revert StrikeOutsideDomain(strikeWad);
        }
        if (timeSeconds > MAX_TIME_SECONDS) revert TimeOutsideDomain(timeSeconds);
        if (
            volatilityWad > MAX_VOLATILITY_WAD
                || (volatilityWad != 0 && volatilityWad < MIN_VOLATILITY_WAD)
        ) {
            revert VolatilityOutsideDomain(volatilityWad);
        }
    }
}
