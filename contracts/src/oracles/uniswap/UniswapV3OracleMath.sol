// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { FullMath } from "../../libraries/FullMath.sol";
import { UniswapV3TickMath } from "./UniswapV3TickMath.sol";

/// @notice Minimal V3 cumulative-observation and tick-quote math for AquaVol.
/// @dev Adapted from github.com/Uniswap/v3-periphery/blob/
/// 0682387198a24c7cd63566a2c58398533860a5d1/contracts/libraries/OracleLibrary.sol.
/// AquaVol modifications (2026-09-26): Solidity 0.8.30, split pure cumulative
/// processing from pool access, and explicit malformed/zero-delta errors.
library UniswapV3OracleMath {
    error InvalidWindow();
    error InvalidObservationResponse();
    error ZeroSecondsPerLiquidityDelta();
    error MeanTickOutOfRange(int56 meanTick);
    error HarmonicLiquidityOverflow(uint192 harmonicMeanLiquidity);

    function fromCumulatives(
        int56[] memory tickCumulatives,
        uint160[] memory secondsPerLiquidityCumulativeX128s,
        uint32 secondsAgo
    ) internal pure returns (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) {
        if (secondsAgo == 0) revert InvalidWindow();
        if (tickCumulatives.length != 2 || secondsPerLiquidityCumulativeX128s.length != 2) {
            revert InvalidObservationResponse();
        }

        int56 tickCumulativeDelta;
        uint160 secondsPerLiquidityDelta;
        // The V3 accumulators intentionally wrap at their declared widths.
        unchecked {
            tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
            secondsPerLiquidityDelta =
                secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];
        }
        int56 secondsAgoSigned = int56(uint56(secondsAgo));
        int56 meanTick = tickCumulativeDelta / secondsAgoSigned;
        if (tickCumulativeDelta < 0 && tickCumulativeDelta % secondsAgoSigned != 0) {
            --meanTick;
        }
        if (meanTick < -887272 || meanTick > 887272) revert MeanTickOutOfRange(meanTick);
        arithmeticMeanTick = int24(meanTick);

        if (secondsPerLiquidityDelta == 0) revert ZeroSecondsPerLiquidityDelta();

        uint192 secondsAgoX160 = uint192(secondsAgo) * type(uint160).max;
        uint192 harmonicLiquidity = secondsAgoX160 / (uint192(secondsPerLiquidityDelta) << 32);
        if (harmonicLiquidity > type(uint128).max) {
            revert HarmonicLiquidityOverflow(harmonicLiquidity);
        }
        harmonicMeanLiquidity = uint128(harmonicLiquidity);
    }

    function quoteAtTick(int24 tick, uint128 baseAmount, address baseToken, address quoteToken)
        internal
        pure
        returns (uint256 quoteAmount)
    {
        uint160 sqrtRatioX96 = UniswapV3TickMath.getSqrtRatioAtTick(tick);

        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
