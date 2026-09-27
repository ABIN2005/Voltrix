// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import {
    ISwapRouter02Minimal,
    IUniswapV3FactoryDeployment
} from "../src/deployment/interfaces/IUniswapV3Deployment.sol";
import { IUniswapV3PoolMinimal } from "../src/oracles/uniswap/interfaces/IUniswapV3Minimal.sol";
import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Stage 4 proves the full TWAP window exists and writes a fresh observation.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract WriteTwapObservation is BaseSepoliaBroadcast {
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    address private constant POOL = 0x0d9516aA182Aa72284802372afaa943E9E77A6D0;
    uint256 private constant AMOUNT_IN = 1e6;
    uint256 private constant MINIMUM_WETH_OUT = 0.0002 ether;

    error UnexpectedPool();
    error InsufficientQuoteBalance(uint256 actual, uint256 required);

    event TwapObservationWritten(
        address indexed pool,
        uint256 quoteAmountIn,
        uint256 wethAmountOut,
        uint16 observationIndex,
        uint16 observationCardinality
    );

    function run() external returns (uint256 wethAmountOut) {
        (address operator, uint256 privateKey) = _prepareBroadcast();
        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();
        AquaVolDemoUSDC quote = AquaVolDemoUSDC(DEMO_USDC);
        IUniswapV3PoolMinimal pool = IUniswapV3PoolMinimal(POOL);

        address token0 = pool.token0();
        address token1 = pool.token1();
        address expectedToken0 =
            DEMO_USDC < externalContracts.weth ? DEMO_USDC : externalContracts.weth;
        address expectedToken1 =
            DEMO_USDC < externalContracts.weth ? externalContracts.weth : DEMO_USDC;
        if (
            token0 != expectedToken0 || token1 != expectedToken1
                || pool.fee() != BaseSepoliaConfig.POOL_FEE
                || IUniswapV3FactoryDeployment(externalContracts.factory)
                        .getPool(DEMO_USDC, externalContracts.weth, BaseSepoliaConfig.POOL_FEE)
                    != POOL
        ) revert UnexpectedPool();
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = BaseSepoliaConfig.TWAP_WINDOW;
        pool.observe(secondsAgos);

        uint256 balance = quote.balanceOf(operator);
        if (balance < AMOUNT_IN) revert InsufficientQuoteBalance(balance, AMOUNT_IN);

        VM.startBroadcast(privateKey);
        require(quote.approve(externalContracts.swapRouter, AMOUNT_IN), "quote approval failed");
        wethAmountOut = ISwapRouter02Minimal(externalContracts.swapRouter)
            .exactInputSingle(
                ISwapRouter02Minimal.ExactInputSingleParams({
                    tokenIn: DEMO_USDC,
                    tokenOut: externalContracts.weth,
                    fee: BaseSepoliaConfig.POOL_FEE,
                    recipient: operator,
                    amountIn: AMOUNT_IN,
                    amountOutMinimum: MINIMUM_WETH_OUT,
                    sqrtPriceLimitX96: 0
                })
            );
        VM.stopBroadcast();

        (,, uint16 observationIndex, uint16 observationCardinality,,,) = pool.slot0();
        emit TwapObservationWritten(
            POOL, AMOUNT_IN, wethAmountOut, observationIndex, observationCardinality
        );
    }
}
