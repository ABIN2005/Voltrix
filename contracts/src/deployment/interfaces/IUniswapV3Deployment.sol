// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

/// @notice Minimal interfaces adapted for AquaVol deployment from Uniswap V3 core/periphery.
/// @dev Core revision: d0831dc6b8a318df3872b6d68f6de135c9f3ec29.
/// Periphery revision: 0682387198a24c7cd63566a2c58398533860a5d1.
/// AquaVol modification (2026-09-26): retain only identity, pool creation, and mint selectors.
interface IUniswapV3FactoryDeployment {
    function getPool(address tokenA, address tokenB, uint24 fee)
        external
        view
        returns (address pool);

    function feeAmountTickSpacing(uint24 fee) external view returns (int24 tickSpacing);

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IUniswapV3PeripheryIdentity {
    function factory() external view returns (address);

    function WETH9() external view returns (address);
}

interface IUniswapV3PoolDeployment {
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}

interface INonfungiblePositionManagerMinimal is IUniswapV3PeripheryIdentity {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IWETH9Minimal {
    function deposit() external payable;

    function withdraw(uint256 amount) external;

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function decimals() external view returns (uint8);
}

interface ISwapRouter02Minimal is IUniswapV3PeripheryIdentity {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}
