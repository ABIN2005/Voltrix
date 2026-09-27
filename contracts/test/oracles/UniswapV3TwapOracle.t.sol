// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import { UniswapV3OracleMath } from "../../src/oracles/uniswap/UniswapV3OracleMath.sol";
import { UniswapV3TwapOracle } from "../../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import {
    MockDecimalsToken,
    MockUniswapV3Factory,
    MockUniswapV3Pool
} from "./mocks/MockUniswapV3.sol";

interface OracleTestVm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;

    function warp(uint256 newTimestamp) external;
}

contract UniswapV3OracleMathHarness {
    function quoteAtTick(int24 tick, uint128 amount, address baseToken, address quoteToken)
        external
        pure
        returns (uint256)
    {
        return UniswapV3OracleMath.quoteAtTick(tick, amount, baseToken, quoteToken);
    }

    function meanFromDelta(int56 tickDelta, uint32 window) external pure returns (int24 meanTick) {
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[1] = tickDelta;
        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);
        secondsPerLiquidityCumulativeX128s[1] = 1 << 32;
        (meanTick,) = UniswapV3OracleMath.fromCumulatives(
            tickCumulatives, secondsPerLiquidityCumulativeX128s, window
        );
    }
}

contract UniswapV3TwapOracleTest {
    OracleTestVm private constant VM =
        OracleTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint24 private constant FEE = 3000;
    uint32 private constant WINDOW = 1800;
    uint32 private constant MAX_AGE = 120;
    uint128 private constant TARGET_LIQUIDITY = 1_000_000_000_000;
    uint128 private constant MIN_LIQUIDITY = 900_000_000_000;
    uint24 private constant MAX_DEVIATION = 500;
    uint32 private constant NOW = 1_000_000;
    int24 private constant DEMO_TICK = 193892;

    // Fixed addresses make both token-order directions explicit and independent of CREATE ordering.
    address private constant QUOTE_LOW = address(0x1000);
    address private constant BASE_HIGH = address(0x2000);
    address private constant BASE_LOW = address(0x3000);
    address private constant QUOTE_HIGH = address(0x4000);

    MockUniswapV3Factory private factory;
    MockUniswapV3Pool private pool;
    UniswapV3TwapOracle private oracle;

    function setUp() public {
        VM.warp(NOW);
        _installToken(QUOTE_LOW, 6);
        _installToken(BASE_HIGH, 18);

        factory = new MockUniswapV3Factory();
        pool = new MockUniswapV3Pool(BASE_HIGH, QUOTE_LOW, FEE);
        factory.setPool(BASE_HIGH, QUOTE_LOW, FEE, address(pool));
        _configureHealthyPool(pool, DEMO_TICK);
        oracle = _deployOracle(factory, pool, BASE_HIGH, QUOTE_LOW, MIN_LIQUIDITY, MAX_DEVIATION);
    }

    function testRoundsPositiveMeanTickTowardNegativeInfinity() public {
        UniswapV3OracleMathHarness harness = new UniswapV3OracleMathHarness();
        int56 delta = int56(int256(uint256(WINDOW) * 100 + 1));
        require(harness.meanFromDelta(delta, WINDOW) == 100, "positive mean tick");
    }

    function testRoundsNegativeMeanTickTowardNegativeInfinity() public {
        UniswapV3OracleMathHarness harness = new UniswapV3OracleMathHarness();
        int56 delta = -int56(int256(uint256(WINDOW) * 100 + 1));
        require(harness.meanFromDelta(delta, WINDOW) == -101, "negative mean tick");
    }

    function testCanonicalTickQuoteVectors() public {
        UniswapV3OracleMathHarness harness = new UniswapV3OracleMathHarness();
        require(harness.quoteAtTick(0, 1e18, address(1), address(2)) == 1e18, "tick zero");
        // Independent Decimal reference: floor(1e18 * 1.0001^6931).
        require(
            harness.quoteAtTick(6931, 1e18, address(1), address(2)) == 1_999_836_340_196_927_629,
            "positive vector"
        );
        // Independent Decimal reference: floor(1e18 / 1.0001^6931).
        require(
            harness.quoteAtTick(6931, 1e18, address(2), address(1)) == 500_040_918_299_108_479,
            "inverted vector"
        );
    }

    function testReadsPositiveTickAndNormalizesSixDecimalsToWad() public view {
        UniswapV3TwapOracle.Observation memory result = oracle.read();
        require(result.arithmeticMeanTick == DEMO_TICK, "mean tick");
        require(result.priceWad == 3_800_129_831e12, "normalized price");
        require(result.harmonicMeanLiquidity >= TARGET_LIQUIDITY, "harmonic liquidity");
        require(result.windowStart == NOW - WINDOW, "window start");
        require(result.windowEnd == NOW, "window end");
        require(result.latestObservationTime == NOW - 30, "latest observation");
    }

    function testInvertsForBaseTokenBelowQuoteToken() public {
        _installToken(BASE_LOW, 18);
        _installToken(QUOTE_HIGH, 6);
        MockUniswapV3Factory reverseFactory = new MockUniswapV3Factory();
        MockUniswapV3Pool reversePool = new MockUniswapV3Pool(BASE_LOW, QUOTE_HIGH, FEE);
        reverseFactory.setPool(BASE_LOW, QUOTE_HIGH, FEE, address(reversePool));
        _configureHealthyPool(reversePool, -DEMO_TICK);
        UniswapV3TwapOracle reverseOracle = _deployOracle(
            reverseFactory, reversePool, BASE_LOW, QUOTE_HIGH, MIN_LIQUIDITY, MAX_DEVIATION
        );

        UniswapV3TwapOracle.Observation memory result = reverseOracle.read();
        require(result.arithmeticMeanTick == -DEMO_TICK, "reverse mean tick");
        require(result.priceWad == 3_800_129_831e12, "reverse normalized price");
    }

    function testRejectsNonzeroCardinalityWithoutFullWindow() public {
        pool.setObservationWindow(
            WINDOW - 1,
            0,
            int56(int256(DEMO_TICK) * int256(uint256(WINDOW))),
            0,
            _secondsPerLiquidityDelta(TARGET_LIQUIDITY)
        );
        _expectReadRevert(MockUniswapV3Pool.HistoryUnavailable.selector);
    }

    function testRejectsUninitializedLatestObservation() public {
        pool.setLatestObservation(NOW - 30, false);
        _expectReadRevert(UniswapV3TwapOracle.LatestObservationUninitialized.selector);
    }

    function testRejectsZeroDatedLatestObservation() public {
        pool.setLatestObservation(0, true);
        _expectReadRevert(UniswapV3TwapOracle.LatestObservationZeroDated.selector);
    }

    function testRejectsStaleLatestObservation() public {
        pool.setLatestObservation(NOW - MAX_AGE - 1, true);
        _expectReadRevert(UniswapV3TwapOracle.LatestObservationTooOld.selector);
    }

    function testRejectsFutureLatestObservation() public {
        pool.setLatestObservation(NOW + 1, true);
        _expectReadRevert(UniswapV3TwapOracle.LatestObservationInFuture.selector);
    }

    function testRejectsZeroCurrentLiquidity() public {
        pool.setLiquidity(0);
        _expectReadRevert(UniswapV3TwapOracle.CurrentLiquidityZero.selector);
    }

    function testRejectsUninitializedPoolPrice() public {
        pool.setSqrtPriceX96(0);
        _expectReadRevert(UniswapV3TwapOracle.PoolUninitialized.selector);
    }

    function testRejectsMalformedObservationResponse() public {
        pool.setMalformedObservationResponse(true);
        _expectReadRevert(UniswapV3OracleMath.InvalidObservationResponse.selector);
    }

    function testRejectsLowHarmonicLiquidity() public {
        UniswapV3TwapOracle strictOracle = _deployOracle(
            factory, pool, BASE_HIGH, QUOTE_LOW, TARGET_LIQUIDITY * 2, MAX_DEVIATION
        );
        _expectReadRevertFrom(strictOracle, UniswapV3TwapOracle.HarmonicLiquidityTooLow.selector);
    }

    function testRejectsCurrentTickDeviation() public {
        pool.setSlot0(DEMO_TICK + int24(MAX_DEVIATION) + 1, 0, 2);
        _expectReadRevert(UniswapV3TwapOracle.TickDeviationTooHigh.selector);
    }

    function testZeroDeviationSettingDisablesCircuitBreaker() public {
        UniswapV3TwapOracle noDeviationOracle =
            _deployOracle(factory, pool, BASE_HIGH, QUOTE_LOW, MIN_LIQUIDITY, 0);
        pool.setSlot0(DEMO_TICK + 10_000, 0, 2);
        require(noDeviationOracle.read().priceWad == 3_800_129_831e12, "disabled breaker");
    }

    function testRevalidatesFactoryIdentityOnEveryRead() public {
        factory.setPool(BASE_HIGH, QUOTE_LOW, FEE, address(0));
        _expectReadRevert(UniswapV3TwapOracle.FactoryPoolMismatch.selector);
    }

    function testRevalidatesPairOnEveryRead() public {
        pool.setIdentity(QUOTE_LOW, address(0x9999), FEE);
        _expectReadRevert(UniswapV3TwapOracle.PoolPairMismatch.selector);
    }

    function testRevalidatesFeeOnEveryRead() public {
        pool.setIdentity(QUOTE_LOW, BASE_HIGH, FEE + 1);
        _expectReadRevert(UniswapV3TwapOracle.PoolFeeMismatch.selector);
    }

    function testConstructorRejectsWrongFactoryPool() public {
        factory.setPool(BASE_HIGH, QUOTE_LOW, FEE, address(0));
        try new UniswapV3TwapOracle(
            address(factory),
            address(pool),
            BASE_HIGH,
            QUOTE_LOW,
            FEE,
            WINDOW,
            MIN_LIQUIDITY,
            MAX_AGE,
            MAX_DEVIATION
        ) returns (
            UniswapV3TwapOracle
        ) {
            revert("constructor succeeded");
        } catch (bytes memory reason) {
            _requireSelector(reason, UniswapV3TwapOracle.FactoryPoolMismatch.selector);
        }
    }

    function testConstructorRejectsWrongDecimals() public {
        address badBase = address(0x5000);
        _installToken(badBase, 8);
        MockUniswapV3Pool badPool = new MockUniswapV3Pool(badBase, QUOTE_LOW, FEE);
        factory.setPool(badBase, QUOTE_LOW, FEE, address(badPool));
        try new UniswapV3TwapOracle(
            address(factory),
            address(badPool),
            badBase,
            QUOTE_LOW,
            FEE,
            WINDOW,
            MIN_LIQUIDITY,
            MAX_AGE,
            MAX_DEVIATION
        ) returns (
            UniswapV3TwapOracle
        ) {
            revert("constructor succeeded");
        } catch (bytes memory reason) {
            _requireSelector(reason, UniswapV3TwapOracle.InvalidTokenDecimals.selector);
        }
    }

    function testRejectsZeroAndExcessivePrices() public {
        _setMeanTick(-887272);
        _expectReadRevert(UniswapV3TwapOracle.PriceOutsideBounds.selector);

        _setMeanTick(887272);
        _expectReadRevert(UniswapV3TwapOracle.PriceOutsideBounds.selector);
    }

    function testReadDoesNotMutatePoolStateOrCallTokens() public view {
        int24 tickBefore = pool.currentTick();
        uint32 timestampBefore = pool.latestObservationTime();
        uint128 liquidityBefore = pool.liquidity();
        address factoryPoolBefore = factory.getPool(BASE_HIGH, QUOTE_LOW, FEE);

        oracle.read();

        require(pool.currentTick() == tickBefore, "tick mutated");
        require(pool.latestObservationTime() == timestampBefore, "observation mutated");
        require(pool.liquidity() == liquidityBefore, "liquidity mutated");
        require(factory.getPool(BASE_HIGH, QUOTE_LOW, FEE) == factoryPoolBefore, "factory mutated");
        // The installed token runtimes expose only decimals(); any attempted transfer call reverts.
    }

    function _deployOracle(
        MockUniswapV3Factory factory_,
        MockUniswapV3Pool pool_,
        address baseToken,
        address quoteToken,
        uint128 minimumLiquidity,
        uint24 maximumDeviation
    ) private returns (UniswapV3TwapOracle) {
        return new UniswapV3TwapOracle(
            address(factory_),
            address(pool_),
            baseToken,
            quoteToken,
            FEE,
            WINDOW,
            minimumLiquidity,
            MAX_AGE,
            maximumDeviation
        );
    }

    function _configureHealthyPool(MockUniswapV3Pool targetPool, int24 meanTick) private {
        targetPool.setSlot0(meanTick, 0, 2);
        targetPool.setLiquidity(TARGET_LIQUIDITY * 2);
        targetPool.setLatestObservation(NOW - 30, true);
        targetPool.setObservationWindow(
            WINDOW,
            0,
            int56(int256(meanTick) * int256(uint256(WINDOW))),
            0,
            _secondsPerLiquidityDelta(TARGET_LIQUIDITY)
        );
    }

    function _setMeanTick(int24 meanTick) private {
        pool.setSlot0(meanTick, 0, 2);
        pool.setObservationWindow(
            WINDOW,
            0,
            int56(int256(meanTick) * int256(uint256(WINDOW))),
            0,
            _secondsPerLiquidityDelta(TARGET_LIQUIDITY)
        );
    }

    function _secondsPerLiquidityDelta(uint128 targetLiquidity) private pure returns (uint160) {
        return uint160((uint256(WINDOW) * type(uint160).max) / (uint256(targetLiquidity) << 32));
    }

    function _installToken(address target, uint8 decimals) private {
        MockDecimalsToken template = new MockDecimalsToken(decimals);
        VM.etch(target, address(template).code);
    }

    function _expectReadRevert(bytes4 expectedSelector) private view {
        _expectReadRevertFrom(oracle, expectedSelector);
    }

    function _expectReadRevertFrom(UniswapV3TwapOracle targetOracle, bytes4 expectedSelector)
        private
        view
    {
        (bool success, bytes memory reason) =
            address(targetOracle).staticcall(abi.encodeCall(UniswapV3TwapOracle.read, ()));
        require(!success, "read succeeded");
        _requireSelector(reason, expectedSelector);
    }

    function _requireSelector(bytes memory reason, bytes4 expectedSelector) private pure {
        require(reason.length >= 4, "missing revert selector");
        bytes4 actualSelector;
        assembly ("memory-safe") {
            actualSelector := mload(add(reason, 0x20))
        }
        require(actualSelector == expectedSelector, "wrong revert selector");
    }
}
