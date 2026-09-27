// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { FullMath } from "../libraries/FullMath.sol";

/// @notice Deterministic Uniswap V3 initialization math for reviewed deployment inputs.
library UniswapV3DeploymentMath {
    error ZeroAmount();
    error SqrtPriceOverflow(uint256 value);

    function encodeSqrtRatioX96(uint256 amount1, uint256 amount0) internal pure returns (uint160) {
        if (amount0 == 0 || amount1 == 0) revert ZeroAmount();
        uint256 ratioX192 = FullMath.mulDiv(amount1, uint256(1) << 192, amount0);
        uint256 sqrtRatioX96 = _sqrt(ratioX192);
        if (sqrtRatioX96 > type(uint160).max) revert SqrtPriceOverflow(sqrtRatioX96);
        // The preceding explicit bound makes this narrowing conversion safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint160(sqrtRatioX96);
    }

    function _sqrt(uint256 value) private pure returns (uint256 result) {
        if (value == 0) return 0;
        // This intentionally calculates two raised to half the value's highest-set-bit index.
        // forge-lint: disable-next-line(incorrect-shift)
        result = 1 << ((255 - _clz(value)) / 2);
        unchecked {
            for (uint256 i = 0; i < 8; ++i) {
                result = (result + value / result) >> 1;
            }
            uint256 roundedDown = value / result;
            if (roundedDown < result) result = roundedDown;
        }
    }

    function _clz(uint256 value) private pure returns (uint256 count) {
        if (value >> 128 == 0) {
            count += 128;
            value <<= 128;
        }
        if (value >> 192 == 0) {
            count += 64;
            value <<= 64;
        }
        if (value >> 224 == 0) {
            count += 32;
            value <<= 32;
        }
        if (value >> 240 == 0) {
            count += 16;
            value <<= 16;
        }
        if (value >> 248 == 0) {
            count += 8;
            value <<= 8;
        }
        if (value >> 252 == 0) {
            count += 4;
            value <<= 4;
        }
        if (value >> 254 == 0) {
            count += 2;
            value <<= 2;
        }
        if (value >> 255 == 0) count += 1;
    }
}
