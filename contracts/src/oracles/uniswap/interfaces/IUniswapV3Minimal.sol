// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

/// @notice Minimal interfaces adapted for AquaVol from Uniswap V3 core.
/// @dev Upstream revision: d0831dc6b8a318df3872b6d68f6de135c9f3ec29.
/// Sources: github.com/Uniswap/v3-core/blob/d0831dc6b8a318df3872b6d68f6de135c9f3ec29/
/// contracts/interfaces/IUniswapV3Factory.sol and contracts/interfaces/IUniswapV3Pool.sol.
/// AquaVol modification (2026-09-26): retain only selectors used by the TWAP adapter.
interface IUniswapV3FactoryMinimal {
    function getPool(address tokenA, address tokenB, uint24 fee)
        external
        view
        returns (address pool);
}

interface IUniswapV3PoolMinimal {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function fee() external view returns (uint24);

    function liquidity() external view returns (uint128);

    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );

    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        );
}

interface IERC20DecimalsMinimal {
    function decimals() external view returns (uint8);
}
