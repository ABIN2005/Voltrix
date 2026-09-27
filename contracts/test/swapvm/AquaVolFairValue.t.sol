// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol fair-value opcode tests added 2026-09-26.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { BlackScholes } from "../../src/pricing/BlackScholes.sol";
import { AquaVolFairValue, IAquaVolSpotOracle } from "../../src/swapvm/AquaVolFairValue.sol";
import { AquaVolOpcode } from "../../src/swapvm/AquaVolOpcode.sol";
import { AquaVolOpcodes } from "../../src/swapvm/AquaVolOpcodes.sol";
import { AquaVolPricingEngine } from "../../src/swapvm/AquaVolPricingEngine.sol";

interface FairValueVm {
    function warp(uint256 newTimestamp) external;
}

contract MockFairValueSeries {
    address public underlying;
    address public quoteAsset;
    uint256 public strikePriceWad;
    uint256 public expiry;

    constructor(
        address underlying_,
        address quoteAsset_,
        uint256 strikePriceWad_,
        uint256 expiry_
    ) {
        underlying = underlying_;
        quoteAsset = quoteAsset_;
        strikePriceWad = strikePriceWad_;
        expiry = expiry_;
    }

    function setUnderlying(address value) external {
        underlying = value;
    }

    function setQuoteAsset(address value) external {
        quoteAsset = value;
    }

    function setExpiry(uint256 value) external {
        expiry = value;
    }
}

contract MockFairValueOracle is IAquaVolSpotOracle {
    address public override BASE_TOKEN;
    address public override QUOTE_TOKEN;
    uint256 public priceWad;
    bool public shouldRevert;

    error RejectedSpot();

    constructor(address baseToken, address quoteToken, uint256 priceWad_) {
        BASE_TOKEN = baseToken;
        QUOTE_TOKEN = quoteToken;
        priceWad = priceWad_;
    }

    function setBaseToken(address value) external {
        BASE_TOKEN = value;
    }

    function setQuoteToken(address value) external {
        QUOTE_TOKEN = value;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function read() external view returns (Observation memory result) {
        if (shouldRevert) revert RejectedSpot();
        result.priceWad = priceWad;
    }
}

    contract MockFairValueRegistry {
        uint256 public volatilityWad;
        uint64 public updatedAt;

        function set(uint256 volatilityWad_, uint64 updatedAt_) external {
            volatilityWad = volatilityWad_;
            updatedAt = updatedAt_;
        }

        function read(address) external view returns (uint256, uint64) {
            return (volatilityWad, updatedAt);
        }
    }

    contract AquaVolFairValueHarness is AquaVolOpcodes {
        uint256 public marker = 7;

        constructor(address pricingEngine) AquaVolOpcodes(pricingEngine) { }

        function build(
            address callToken,
            address quoteToken,
            address oracle,
            address registry,
            uint256 maximumAge
        ) external pure returns (bytes memory) {
            return AquaVolFairValue.build(callToken, quoteToken, oracle, registry, maximumAge);
        }

        function run(
            bytes calldata args,
            address tokenIn,
            address tokenOut,
            bool isExactIn,
            uint256 balanceIn,
            uint256 balanceOut,
            uint256 amountIn,
            uint256 amountOut
        ) external returns (uint256 resultingAmountIn, uint256 resultingAmountOut) {
            Context memory ctx;
            ctx.query.tokenIn = tokenIn;
            ctx.query.tokenOut = tokenOut;
            ctx.query.isExactIn = isExactIn;
            ctx.swap.balanceIn = balanceIn;
            ctx.swap.balanceOut = balanceOut;
            ctx.swap.amountIn = amountIn;
            ctx.swap.amountOut = amountOut;
            _runOpcode(ctx, AquaVolOpcode.OPTION_FAIR_VALUE, args);
            return (ctx.swap.amountIn, ctx.swap.amountOut);
        }
    }

    contract AquaVolFairValueTest {
        FairValueVm private constant VM =
            FairValueVm(address(uint160(uint256(keccak256("hevm cheat code")))));

        uint256 private constant NOW = 1_000_000;
        uint256 private constant MAXIMUM_AGE = 1 hours;
        uint256 private constant VOLATILITY = 0.64e18;
        uint256 private constant SPOT = 3_800e18;
        uint256 private constant STRIKE = 4_000e18;
        uint256 private constant ONE_CALL = 1e18;
        uint256 private constant QUOTE_SCALE = 1e30;

        AquaVolFairValueHarness private harness;
        MockERC20 private underlying;
        MockERC20 private quote;
        MockFairValueSeries private series;
        MockFairValueOracle private oracle;
        MockFairValueRegistry private registry;

        function setUp() public {
            VM.warp(NOW);
            harness = new AquaVolFairValueHarness(address(new AquaVolPricingEngine()));
            underlying = new MockERC20("Wrapped Ether", "WETH", 18);
            quote = new MockERC20("USD Coin", "USDC", 6);
            series = _deploySeries();
            oracle = new MockFairValueOracle(address(underlying), address(quote), SPOT);
            registry = new MockFairValueRegistry();
            registry.set(VOLATILITY, uint64(NOW));
        }

        function testCanonicalBuilderEncoding() public view {
            bytes memory instruction = harness.build(
                address(series), address(quote), address(oracle), address(registry), MAXIMUM_AGE
            );
            bytes memory expected = bytes.concat(
                hex"d1a0",
                abi.encode(
                    address(series), address(quote), address(oracle), address(registry), MAXIMUM_AGE
                )
            );
            require(keccak256(instruction) == keccak256(expected), "fair-value encoding");
        }

        function testBuyUsesCeilingAndSellBackUsesFloorRounding() public {
            uint256 callAmount = ONE_CALL + 1;
            uint256 premiumWad = BlackScholes.callPrice(SPOT, STRIKE, 7 days, VOLATILITY);
            uint256 floorQuote = callAmount * premiumWad / QUOTE_SCALE;
            uint256 ceilQuote = floorQuote + 1;
            bytes memory args = _args(MAXIMUM_AGE);

            (uint256 buyInput, uint256 buyOutput) = harness.run(
                args, address(quote), address(series), false, 5_000e6, 10e18, 0, callAmount
            );
            require(buyInput == ceilQuote, "buy not rounded upward");
            require(buyOutput == callAmount, "buy output changed");

            (uint256 sellInput, uint256 sellOutput) = harness.run(
                args, address(series), address(quote), true, 10e18, 5_000e6, callAmount, 0
            );
            require(sellInput == callAmount, "sell input changed");
            require(sellOutput == floorQuote, "sell not rounded downward");
        }

        function testRejectsWrongDirectionModeZeroAmountAndLiquidity() public {
            bytes memory args = _args(MAXIMUM_AGE);
            _expectRevert(
                args,
                address(underlying),
                address(series),
                false,
                0,
                ONE_CALL,
                AquaVolFairValue.UnsupportedPair.selector
            );
            _expectRevert(
                args,
                address(quote),
                address(series),
                true,
                ONE_CALL,
                0,
                AquaVolFairValue.UnsupportedSwapMode.selector
            );
            _expectRevert(
                args,
                address(series),
                address(quote),
                false,
                0,
                ONE_CALL,
                AquaVolFairValue.UnsupportedSwapMode.selector
            );
            _expectRevert(
                args,
                address(quote),
                address(series),
                false,
                0,
                0,
                AquaVolFairValue.ZeroCallAmount.selector
            );
            _expectRevert(
                args,
                address(quote),
                address(series),
                false,
                0,
                10e18 + 1,
                AquaVolFairValue.InsufficientOutputLiquidity.selector
            );
            _expectRevert(
                args,
                address(series),
                address(quote),
                true,
                1e30,
                0,
                AquaVolFairValue.InsufficientOutputLiquidity.selector
            );
        }

        function testRejectsMissingStaleAndFutureVolatility() public {
            registry.set(0, 0);
            _expectHealthyBuyRevert(AquaVolFairValue.VolatilityMissing.selector);

            registry.set(VOLATILITY, 0);
            _expectHealthyBuyRevert(AquaVolFairValue.VolatilityTimestampMissing.selector);

            registry.set(VOLATILITY, uint64(NOW - MAXIMUM_AGE - 1));
            _expectHealthyBuyRevert(AquaVolFairValue.VolatilityStale.selector);

            registry.set(VOLATILITY, uint64(NOW + 16));
            _expectHealthyBuyRevert(AquaVolFairValue.VolatilityTimestampTooFarInFuture.selector);

            registry.set(5e18 + 1, uint64(NOW));
            _expectHealthyBuyRevert(AquaVolFairValue.VolatilityOutOfRange.selector);

            registry.set(0.0001e18 - 1, uint64(NOW));
            _expectHealthyBuyRevert(AquaVolFairValue.VolatilityOutOfRange.selector);
        }

        function testAcceptsFifteenSecondFutureVolatilityTimestamp() public {
            registry.set(VOLATILITY, uint64(NOW + 15));
            (uint256 amountIn,) = harness.run(
                _args(MAXIMUM_AGE), address(quote), address(series), false, 0, ONE_CALL, 0, ONE_CALL
            );
            require(amountIn != 0, "future tolerance rejected");
        }

        function testRejectsExpiredSeriesAndPropagatesGuardedOracleFailure() public {
            series.setExpiry(NOW);
            _expectHealthyBuyRevert(AquaVolFairValue.SeriesExpired.selector);

            series.setExpiry(NOW + 7 days);
            oracle.setShouldRevert(true);
            _expectHealthyBuyRevert(MockFairValueOracle.RejectedSpot.selector);
        }

        function testRejectsSeriesAndOracleIdentityMismatches() public {
            series.setQuoteAsset(address(underlying));
            _expectHealthyBuyRevert(AquaVolFairValue.SeriesQuoteMismatch.selector);

            series.setQuoteAsset(address(quote));
            oracle.setBaseToken(address(quote));
            _expectHealthyBuyRevert(AquaVolFairValue.OracleBaseMismatch.selector);

            oracle.setBaseToken(address(underlying));
            oracle.setQuoteToken(address(underlying));
            _expectHealthyBuyRevert(AquaVolFairValue.OracleQuoteMismatch.selector);
        }

        function testBuilderRejectsInvalidMaximumAge() public view {
            _expectBuildRevert(0, AquaVolFairValue.InvalidMaximumVolatilityAge.selector);
            _expectBuildRevert(7 days + 1, AquaVolFairValue.InvalidMaximumVolatilityAge.selector);
        }

        function testRuntimeRejectsMalformedArgumentsAndInvalidMaximumAge() public {
            _expectRevert(
                hex"00",
                address(quote),
                address(series),
                false,
                0,
                ONE_CALL,
                AquaVolFairValue.InvalidArgumentsLength.selector
            );
            _expectRevert(
                _args(0),
                address(quote),
                address(series),
                false,
                0,
                ONE_CALL,
                AquaVolFairValue.InvalidMaximumVolatilityAge.selector
            );
        }

        function testSellBackRejectsAmountThatRoundsToZeroQuoteUnits() public {
            _expectRevert(
                _args(MAXIMUM_AGE),
                address(series),
                address(quote),
                true,
                1,
                0,
                AquaVolFairValue.ZeroQuoteAmount.selector
            );
        }

        function testRejectsSecondFairValueInstructionForBothDirections() public {
            _expectRevert(
                _args(MAXIMUM_AGE),
                address(quote),
                address(series),
                false,
                1,
                ONE_CALL,
                AquaVolFairValue.FairValueRegisterAlreadySet.selector
            );
            _expectRevert(
                _args(MAXIMUM_AGE),
                address(series),
                address(quote),
                true,
                ONE_CALL,
                1,
                AquaVolFairValue.FairValueRegisterAlreadySet.selector
            );
        }

        function testInstructionDoesNotMoveTokensOrMutateHarnessStorage() public {
            underlying.mint(address(harness), 2e18);
            quote.mint(address(harness), 100e6);
            uint256 underlyingBefore = underlying.balanceOf(address(harness));
            uint256 quoteBefore = quote.balanceOf(address(harness));
            uint256 markerBefore = harness.marker();

            harness.run(
                _args(MAXIMUM_AGE), address(quote), address(series), false, 100e6, 2e18, 0, ONE_CALL
            );

            require(underlying.balanceOf(address(harness)) == underlyingBefore, "underlying moved");
            require(quote.balanceOf(address(harness)) == quoteBefore, "quote moved");
            require(harness.marker() == markerBefore, "storage mutated");
        }

        function _args(uint256 maximumAge) private view returns (bytes memory) {
            return abi.encode(
                address(series), address(quote), address(oracle), address(registry), maximumAge
            );
        }

        function _deploySeries() private returns (MockFairValueSeries deployedSeries) {
            address base = address(underlying);
            address usd = address(quote);
            uint256 end = NOW + 7 days;
            deployedSeries = new MockFairValueSeries(base, usd, STRIKE, end);
        }

        function _expectHealthyBuyRevert(bytes4 selector) private {
            _expectRevert(
                _args(MAXIMUM_AGE), address(quote), address(series), false, 0, ONE_CALL, selector
            );
        }

        function _expectRevert(
            bytes memory args,
            address tokenIn,
            address tokenOut,
            bool isExactIn,
            uint256 amountIn,
            uint256 amountOut,
            bytes4 selector
        ) private {
            (bool success, bytes memory reason) = address(harness)
                .call(
                    abi.encodeCall(
                        AquaVolFairValueHarness.run,
                        (args, tokenIn, tokenOut, isExactIn, 10e18, 10e18, amountIn, amountOut)
                    )
                );
            require(!success, "expected revert");
            _requireSelector(reason, selector);
        }

        function _expectBuildRevert(uint256 maximumAge, bytes4 selector) private view {
            (bool success, bytes memory reason) = address(harness)
                .staticcall(
                    abi.encodeCall(
                        AquaVolFairValueHarness.build,
                        (
                            address(series),
                            address(quote),
                            address(oracle),
                            address(registry),
                            maximumAge
                        )
                    )
                );
            require(!success, "build succeeded");
            _requireSelector(reason, selector);
        }

        function _requireSelector(bytes memory reason, bytes4 expected) private pure {
            require(reason.length >= 4, "missing selector");
            bytes4 actual;
            assembly ("memory-safe") {
                actual := mload(add(reason, 0x20))
            }
            require(actual == expected, "wrong selector");
        }
    }
