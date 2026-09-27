// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { UniswapV3DeploymentMath } from "../src/deployment/UniswapV3DeploymentMath.sol";
import {
    INonfungiblePositionManagerMinimal,
    IUniswapV3FactoryDeployment,
    IUniswapV3PoolDeployment,
    IWETH9Minimal
} from "../src/deployment/interfaces/IUniswapV3Deployment.sol";
import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Stage 2 funds the operator and creates the bounded WETH/avUSD demo market.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract BootstrapUniswapV3Pool is BaseSepoliaBroadcast {
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    uint256 private constant MINT_AMOUNT = 500e6;
    uint256 private constant WRAP_AMOUNT = 0.2 ether;
    uint256 private constant POOL_WETH = 0.1 ether;
    uint256 private constant POOL_QUOTE = 380e6;
    uint256 private constant MINIMUM_OPERATOR_BALANCE = 0.25 ether;
    uint16 private constant OBSERVATION_CARDINALITY = 16;
    int24 private constant MIN_FULL_RANGE_TICK = -887_220;
    int24 private constant MAX_FULL_RANGE_TICK = 887_220;

    error UnexpectedDemoToken();
    error DemoTokenAlreadyMinted(uint256 supply);
    error PoolAlreadyExists(address pool);
    error InsufficientStageBalance(uint256 actual, uint256 required);

    event PoolBootstrap(
        address indexed pool,
        uint256 indexed positionTokenId,
        uint128 liquidity,
        uint256 wethAmount,
        uint256 quoteAmount,
        uint160 initialSqrtPriceX96
    );

    function run() external returns (address pool, uint256 positionTokenId) {
        (address operator, uint256 privateKey) = _prepareBroadcast();
        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();
        AquaVolDemoUSDC quote = AquaVolDemoUSDC(DEMO_USDC);
        IWETH9Minimal weth = IWETH9Minimal(externalContracts.weth);

        if (
            DEMO_USDC.code.length == 0 || quote.minter() != operator || quote.decimals() != 6
                || keccak256(bytes(quote.symbol())) != keccak256(bytes("avUSD"))
        ) revert UnexpectedDemoToken();
        if (quote.totalSupply() != 0) revert DemoTokenAlreadyMinted(quote.totalSupply());
        if (operator.balance < MINIMUM_OPERATOR_BALANCE) {
            revert InsufficientStageBalance(operator.balance, MINIMUM_OPERATOR_BALANCE);
        }

        IUniswapV3FactoryDeployment factory = IUniswapV3FactoryDeployment(externalContracts.factory);
        address existingPool =
            factory.getPool(address(weth), address(quote), BaseSepoliaConfig.POOL_FEE);
        if (existingPool != address(0)) revert PoolAlreadyExists(existingPool);

        (address token0, address token1) = address(weth) < address(quote)
            ? (address(weth), address(quote))
            : (address(quote), address(weth));
        uint256 amount0ForPrice = token0 == address(weth) ? 1e18 : 3_800e6;
        uint256 amount1ForPrice = token1 == address(quote) ? 3_800e6 : 1e18;
        uint160 sqrtPriceX96 =
            UniswapV3DeploymentMath.encodeSqrtRatioX96(amount1ForPrice, amount0ForPrice);

        INonfungiblePositionManagerMinimal manager =
            INonfungiblePositionManagerMinimal(externalContracts.positionManager);
        VM.startBroadcast(privateKey);
        quote.mint(operator, MINT_AMOUNT);
        weth.deposit{ value: WRAP_AMOUNT }();
        pool = manager.createAndInitializePoolIfNecessary(
            token0, token1, BaseSepoliaConfig.POOL_FEE, sqrtPriceX96
        );
        IUniswapV3PoolDeployment(pool).increaseObservationCardinalityNext(OBSERVATION_CARDINALITY);
        require(weth.approve(address(manager), POOL_WETH), "WETH approval failed");
        require(quote.approve(address(manager), POOL_QUOTE), "quote approval failed");

        uint256 amount0Desired = token0 == address(weth) ? POOL_WETH : POOL_QUOTE;
        uint256 amount1Desired = token1 == address(quote) ? POOL_QUOTE : POOL_WETH;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        (positionTokenId, liquidity, amount0, amount1) = manager.mint(
            INonfungiblePositionManagerMinimal.MintParams({
                token0: token0,
                token1: token1,
                fee: BaseSepoliaConfig.POOL_FEE,
                tickLower: MIN_FULL_RANGE_TICK,
                tickUpper: MAX_FULL_RANGE_TICK,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: amount0Desired * 99 / 100,
                amount1Min: amount1Desired * 99 / 100,
                recipient: operator,
                deadline: block.timestamp + 15 minutes
            })
        );
        VM.stopBroadcast();

        require(
            factory.getPool(address(weth), address(quote), BaseSepoliaConfig.POOL_FEE) == pool,
            "factory pool mismatch"
        );
        require(liquidity != 0, "zero liquidity");
        uint256 wethAmount = token0 == address(weth) ? amount0 : amount1;
        uint256 quoteAmount = token0 == address(quote) ? amount0 : amount1;
        emit PoolBootstrap(pool, positionTokenId, liquidity, wethAmount, quoteAmount, sqrtPriceX96);
    }
}
