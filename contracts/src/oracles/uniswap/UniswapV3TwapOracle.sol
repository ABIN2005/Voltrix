// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { FullMath } from "../../libraries/FullMath.sol";
import {
    IERC20DecimalsMinimal,
    IUniswapV3FactoryMinimal,
    IUniswapV3PoolMinimal
} from "./interfaces/IUniswapV3Minimal.sol";
import { UniswapV3OracleMath } from "./UniswapV3OracleMath.sol";

/// @notice Immutable, view-only USDC-per-WETH oracle backed by a complete V3 TWAP window.
/// @dev The cumulative and quote algorithms are isolated in UniswapV3OracleMath, adapted
/// from github.com/Uniswap/v3-periphery/blob/
/// 0682387198a24c7cd63566a2c58398533860a5d1/contracts/libraries/OracleLibrary.sol
/// on 2026-09-26.
contract UniswapV3TwapOracle {
    uint256 public constant MAX_PRICE_WAD = 1_000_000e18;
    uint256 private constant QUOTE_TO_WAD_SCALE = 1e12;

    address public immutable FACTORY;
    address public immutable POOL;
    address public immutable BASE_TOKEN;
    address public immutable QUOTE_TOKEN;
    uint24 public immutable FEE;
    uint32 public immutable TWAP_WINDOW;
    uint128 public immutable MIN_HARMONIC_LIQUIDITY;
    uint32 public immutable MAX_OBSERVATION_AGE;
    uint24 public immutable MAX_TICK_DEVIATION;

    struct Observation {
        uint256 priceWad;
        int24 arithmeticMeanTick;
        uint128 harmonicMeanLiquidity;
        uint32 windowStart;
        uint32 windowEnd;
        uint32 latestObservationTime;
    }

    error ZeroAddress();
    error AddressHasNoCode(address account);
    error IdenticalTokens();
    error InvalidWindow();
    error InvalidMaximumObservationAge();
    error InvalidTokenDecimals(address token, uint8 expected, uint8 actual);
    error FactoryPoolMismatch(address expected, address actual);
    error PoolPairMismatch(address expectedToken0, address expectedToken1);
    error PoolFeeMismatch(uint24 expected, uint24 actual);
    error PoolUninitialized();
    error LatestObservationUninitialized();
    error LatestObservationZeroDated();
    error LatestObservationInFuture(uint32 observationTime, uint32 currentTime);
    error LatestObservationTooOld(uint32 age, uint32 maximumAge);
    error CurrentLiquidityZero();
    error HarmonicLiquidityTooLow(uint128 actual, uint128 minimum);
    error TickDeviationTooHigh(uint256 actual, uint24 maximum);
    error TimestampOutsideUint32(uint256 timestamp);
    error TimestampBeforeWindow(uint32 timestamp, uint32 window);
    error PriceOutsideBounds(uint256 priceWad);

    constructor(
        address factory,
        address pool,
        address baseToken,
        address quoteToken,
        uint24 fee,
        uint32 twapWindow,
        uint128 minHarmonicLiquidity,
        uint32 maxObservationAge,
        uint24 maxTickDeviation
    ) {
        if (
            factory == address(0) || pool == address(0) || baseToken == address(0)
                || quoteToken == address(0)
        ) revert ZeroAddress();
        if (baseToken == quoteToken) revert IdenticalTokens();
        _requireCode(factory);
        _requireCode(pool);
        _requireCode(baseToken);
        _requireCode(quoteToken);
        if (twapWindow == 0) revert InvalidWindow();
        if (maxObservationAge == 0) revert InvalidMaximumObservationAge();

        uint8 baseDecimals = IERC20DecimalsMinimal(baseToken).decimals();
        if (baseDecimals != 18) revert InvalidTokenDecimals(baseToken, 18, baseDecimals);
        uint8 quoteDecimals = IERC20DecimalsMinimal(quoteToken).decimals();
        if (quoteDecimals != 6) revert InvalidTokenDecimals(quoteToken, 6, quoteDecimals);

        FACTORY = factory;
        POOL = pool;
        BASE_TOKEN = baseToken;
        QUOTE_TOKEN = quoteToken;
        FEE = fee;
        TWAP_WINDOW = twapWindow;
        MIN_HARMONIC_LIQUIDITY = minHarmonicLiquidity;
        MAX_OBSERVATION_AGE = maxObservationAge;
        MAX_TICK_DEVIATION = maxTickDeviation;

        _validateIdentity();
    }

    function read() external view returns (Observation memory result) {
        _validateIdentity();

        IUniswapV3PoolMinimal pool = IUniswapV3PoolMinimal(POOL);
        (
            uint160 sqrtPriceX96,
            int24 currentTick,
            uint16 observationIndex,
            uint16 observationCardinality,,,
        ) = pool.slot0();
        if (sqrtPriceX96 == 0 || observationCardinality == 0) revert PoolUninitialized();

        (uint32 latestObservationTime,,, bool initialized) = pool.observations(observationIndex);
        if (!initialized) revert LatestObservationUninitialized();
        if (latestObservationTime == 0) revert LatestObservationZeroDated();
        if (block.timestamp > type(uint32).max) revert TimestampOutsideUint32(block.timestamp);
        uint32 currentTime = uint32(block.timestamp);
        if (latestObservationTime > currentTime) {
            revert LatestObservationInFuture(latestObservationTime, currentTime);
        }
        uint32 observationAge = currentTime - latestObservationTime;
        if (observationAge > MAX_OBSERVATION_AGE) {
            revert LatestObservationTooOld(observationAge, MAX_OBSERVATION_AGE);
        }
        if (currentTime < TWAP_WINDOW) revert TimestampBeforeWindow(currentTime, TWAP_WINDOW);
        if (pool.liquidity() == 0) revert CurrentLiquidityZero();

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = TWAP_WINDOW;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            pool.observe(secondsAgos);
        (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = UniswapV3OracleMath.fromCumulatives(
            tickCumulatives, secondsPerLiquidityCumulativeX128s, TWAP_WINDOW
        );

        if (harmonicMeanLiquidity < MIN_HARMONIC_LIQUIDITY) {
            revert HarmonicLiquidityTooLow(harmonicMeanLiquidity, MIN_HARMONIC_LIQUIDITY);
        }
        if (MAX_TICK_DEVIATION != 0) {
            int256 signedDifference = int256(currentTick) - int256(arithmeticMeanTick);
            uint256 deviation = uint256(signedDifference < 0 ? -signedDifference : signedDifference);
            if (deviation > MAX_TICK_DEVIATION) {
                revert TickDeviationTooHigh(deviation, MAX_TICK_DEVIATION);
            }
        }

        uint256 quoteNative =
            UniswapV3OracleMath.quoteAtTick(arithmeticMeanTick, 1e18, BASE_TOKEN, QUOTE_TOKEN);
        uint256 priceWad = FullMath.mulDiv(quoteNative, QUOTE_TO_WAD_SCALE, 1);
        if (priceWad == 0 || priceWad > MAX_PRICE_WAD) {
            revert PriceOutsideBounds(priceWad);
        }

        result = Observation({
            priceWad: priceWad,
            arithmeticMeanTick: arithmeticMeanTick,
            harmonicMeanLiquidity: harmonicMeanLiquidity,
            windowStart: currentTime - TWAP_WINDOW,
            windowEnd: currentTime,
            latestObservationTime: latestObservationTime
        });
    }

    function _validateIdentity() private view {
        address actualPool = IUniswapV3FactoryMinimal(FACTORY).getPool(BASE_TOKEN, QUOTE_TOKEN, FEE);
        if (actualPool != POOL) revert FactoryPoolMismatch(POOL, actualPool);

        address expectedToken0 = BASE_TOKEN < QUOTE_TOKEN ? BASE_TOKEN : QUOTE_TOKEN;
        address expectedToken1 = BASE_TOKEN < QUOTE_TOKEN ? QUOTE_TOKEN : BASE_TOKEN;
        IUniswapV3PoolMinimal pool = IUniswapV3PoolMinimal(POOL);
        if (pool.token0() != expectedToken0 || pool.token1() != expectedToken1) {
            revert PoolPairMismatch(expectedToken0, expectedToken1);
        }
        uint24 actualFee = pool.fee();
        if (actualFee != FEE) revert PoolFeeMismatch(FEE, actualFee);
    }

    function _requireCode(address account) private view {
        if (account.code.length == 0) revert AddressHasNoCode(account);
    }
}
