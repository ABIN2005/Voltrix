// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol inventory-skew opcode tests added 2026-09-26.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { InventoryPricing } from "../../src/pricing/InventoryPricing.sol";
import { IAquaVolSpotOracle } from "../../src/swapvm/AquaVolFairValue.sol";
import { AquaVolInventorySkew } from "../../src/swapvm/AquaVolInventorySkew.sol";
import { AquaVolOpcode } from "../../src/swapvm/AquaVolOpcode.sol";
import { AquaVolOpcodes } from "../../src/swapvm/AquaVolOpcodes.sol";
import { AquaVolPricingEngine } from "../../src/swapvm/AquaVolPricingEngine.sol";

contract MockInventorySeries is MockERC20 {
    address public underlying;
    address public quoteAsset;

    constructor(address underlying_, address quoteAsset_) MockERC20("AquaVol Call", "avCALL", 18) {
        underlying = underlying_;
        quoteAsset = quoteAsset_;
    }

    function setUnderlying(address value) external {
        underlying = value;
    }

    function setQuoteAsset(address value) external {
        quoteAsset = value;
    }
}

contract MockInventoryOracle is IAquaVolSpotOracle {
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

    function setPriceWad(uint256 value) external {
        priceWad = value;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function read() external view returns (Observation memory result) {
        if (shouldRevert) revert RejectedSpot();
        result.priceWad = priceWad;
    }
}

    contract AquaVolInventorySkewHarness is AquaVolOpcodes {
        uint256 public marker = 7;

        constructor(address pricingEngine) AquaVolOpcodes(pricingEngine) { }

        function build(
            address callToken,
            address quoteToken,
            address oracle,
            uint256 initialInventory,
            uint256 gammaWad,
            uint256 halfSpreadWad
        ) external pure returns (bytes memory) {
            return AquaVolInventorySkew.build(
                callToken, quoteToken, oracle, initialInventory, gammaWad, halfSpreadWad
            );
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
            _runOpcode(ctx, AquaVolOpcode.OPTION_INVENTORY_SKEW, args);
            return (ctx.swap.amountIn, ctx.swap.amountOut);
        }
    }

    contract AquaVolInventorySkewTest {
        uint256 private constant ONE_CALL = 1e18;
        uint256 private constant INITIAL_INVENTORY = 10e18;
        uint256 private constant FAIR_QUOTE = 60_294_027;
        uint256 private constant GAMMA = 0.2e18;
        uint256 private constant SPREAD = 0.01e18;
        uint256 private constant SPOT = 3_800e18;

        AquaVolInventorySkewHarness private harness;
        MockERC20 private underlying;
        MockERC20 private quote;
        MockInventorySeries private series;
        MockInventoryOracle private oracle;

        function setUp() public {
            harness = new AquaVolInventorySkewHarness(address(new AquaVolPricingEngine()));
            underlying = new MockERC20("Wrapped Ether", "WETH", 18);
            quote = new MockERC20("USD Coin", "USDC", 6);
            series = new MockInventorySeries(address(underlying), address(quote));
            oracle = new MockInventoryOracle(address(underlying), address(quote), SPOT);
        }

        function testCanonicalBuilderEncoding() public view {
            bytes memory instruction = harness.build(
                address(series), address(quote), address(oracle), INITIAL_INVENTORY, GAMMA, SPREAD
            );
            bytes memory expected = bytes.concat(
                hex"d2c0",
                abi.encode(
                    address(series),
                    address(quote),
                    address(oracle),
                    INITIAL_INVENTORY,
                    GAMMA,
                    SPREAD
                )
            );
            require(keccak256(instruction) == keccak256(expected), "inventory encoding");
        }

        function testCanonicalBuyConsumesFairValueAndKeepsCallAmount() public {
            (uint256 amountIn, uint256 amountOut) = harness.run(
                _args(),
                address(quote),
                address(series),
                false,
                5_000e6,
                INITIAL_INVENTORY,
                FAIR_QUOTE,
                ONE_CALL
            );
            require(amountIn == 61_505_938, "wrong buy quote");
            require(amountOut == ONE_CALL, "CALL output changed");
        }

        function testCanonicalSellConsumesFairValueAndKeepsCallAmount() public {
            (uint256 amountIn, uint256 amountOut) = harness.run(
                _args(), address(series), address(quote), true, 5e18, 5_000e6, ONE_CALL, FAIR_QUOTE
            );
            require(amountIn == ONE_CALL, "CALL input changed");
            require(amountOut == 65_063_284, "wrong sell quote");
        }

        function testRejectsMissingFairValueForBothDirections() public {
            _expectRevert(
                _args(),
                address(quote),
                address(series),
                false,
                5_000e6,
                INITIAL_INVENTORY,
                0,
                ONE_CALL,
                AquaVolInventorySkew.MissingFairValueQuote.selector
            );
            _expectRevert(
                _args(),
                address(series),
                address(quote),
                true,
                5e18,
                5_000e6,
                ONE_CALL,
                0,
                AquaVolInventorySkew.MissingFairValueQuote.selector
            );
        }

        function testRejectsUnsupportedDirectionAndMode() public {
            _expectRevert(
                _args(),
                address(underlying),
                address(series),
                false,
                0,
                INITIAL_INVENTORY,
                FAIR_QUOTE,
                ONE_CALL,
                AquaVolInventorySkew.UnsupportedPair.selector
            );
            _expectRevert(
                _args(),
                address(quote),
                address(series),
                true,
                0,
                INITIAL_INVENTORY,
                FAIR_QUOTE,
                ONE_CALL,
                AquaVolInventorySkew.UnsupportedSwapMode.selector
            );
            _expectRevert(
                _args(),
                address(series),
                address(quote),
                false,
                5e18,
                5_000e6,
                ONE_CALL,
                FAIR_QUOTE,
                AquaVolInventorySkew.UnsupportedSwapMode.selector
            );
        }

        function testRejectsInventoryTransitionsOutsideConfiguredRange() public {
            _expectRevert(
                _args(),
                address(quote),
                address(series),
                false,
                0,
                ONE_CALL,
                FAIR_QUOTE,
                ONE_CALL + 1,
                InventoryPricing.InventoryTransitionOutsideDomain.selector
            );
            _expectRevert(
                _args(),
                address(series),
                address(quote),
                true,
                INITIAL_INVENTORY,
                5_000e6,
                1,
                FAIR_QUOTE,
                InventoryPricing.InventoryTransitionOutsideDomain.selector
            );
            _expectRevert(
                _args(),
                address(quote),
                address(series),
                false,
                0,
                INITIAL_INVENTORY + 1,
                FAIR_QUOTE,
                ONE_CALL,
                InventoryPricing.CurrentInventoryOutsideDomain.selector
            );
        }

        function testRejectsMalformedAndInvalidConfiguration() public {
            _expectHealthyBuyRevert(hex"00", AquaVolInventorySkew.InvalidArgumentsLength.selector);
            _expectHealthyBuyRevert(
                _argsWith(address(series), address(quote), address(oracle), 0, GAMMA, SPREAD),
                InventoryPricing.InitialInventoryOutsideDomain.selector
            );
            _expectHealthyBuyRevert(
                _argsWith(
                    address(series),
                    address(quote),
                    address(oracle),
                    INITIAL_INVENTORY,
                    1e18 + 1,
                    SPREAD
                ),
                InventoryPricing.GammaOutsideDomain.selector
            );
            _expectHealthyBuyRevert(
                _argsWith(
                    address(series),
                    address(quote),
                    address(oracle),
                    INITIAL_INVENTORY,
                    GAMMA,
                    0.25e18 + 1
                ),
                InventoryPricing.HalfSpreadOutsideDomain.selector
            );
            _expectHealthyBuyRevert(
                _argsWith(
                    address(0), address(quote), address(oracle), INITIAL_INVENTORY, GAMMA, SPREAD
                ),
                AquaVolInventorySkew.InvalidAddress.selector
            );
        }

        function testBuilderRejectsInvalidConfiguration() public view {
            _expectBuildRevert(
                address(0),
                address(quote),
                address(oracle),
                INITIAL_INVENTORY,
                GAMMA,
                SPREAD,
                AquaVolInventorySkew.InvalidAddress.selector
            );
            _expectBuildRevert(
                address(series),
                address(series),
                address(oracle),
                INITIAL_INVENTORY,
                GAMMA,
                SPREAD,
                AquaVolInventorySkew.UnsupportedPair.selector
            );
        }

        function testRejectsSeriesAndOracleIdentityMismatches() public {
            series.setQuoteAsset(address(underlying));
            _expectHealthyBuyRevert(_args(), AquaVolInventorySkew.SeriesQuoteMismatch.selector);

            series.setQuoteAsset(address(quote));
            oracle.setBaseToken(address(quote));
            _expectHealthyBuyRevert(_args(), AquaVolInventorySkew.OracleBaseMismatch.selector);

            oracle.setBaseToken(address(underlying));
            oracle.setQuoteToken(address(underlying));
            _expectHealthyBuyRevert(_args(), AquaVolInventorySkew.OracleQuoteMismatch.selector);
        }

        function testRejectsFinalQuoteAboveSpotAndPropagatesOracleFailure() public {
            oracle.setPriceWad(0.01e18);
            _expectHealthyBuyRevert(_args(), AquaVolInventorySkew.FinalQuoteAboveSpotCap.selector);

            oracle.setPriceWad(SPOT);
            oracle.setShouldRevert(true);
            _expectHealthyBuyRevert(_args(), MockInventoryOracle.RejectedSpot.selector);
        }

        function testSellRejectsInsufficientQuoteLiquidity() public {
            _expectRevert(
                _args(),
                address(series),
                address(quote),
                true,
                5e18,
                65_063_283,
                ONE_CALL,
                FAIR_QUOTE,
                AquaVolInventorySkew.InsufficientOutputLiquidity.selector
            );
        }

        function testInstructionDoesNotMoveTokensOrMutateHarnessStorage() public {
            series.mint(address(harness), 2e18);
            quote.mint(address(harness), 100e6);
            uint256 callBefore = series.balanceOf(address(harness));
            uint256 quoteBefore = quote.balanceOf(address(harness));
            uint256 markerBefore = harness.marker();

            harness.run(
                _args(),
                address(quote),
                address(series),
                false,
                100e6,
                INITIAL_INVENTORY,
                FAIR_QUOTE,
                ONE_CALL
            );

            require(series.balanceOf(address(harness)) == callBefore, "CALL moved");
            require(quote.balanceOf(address(harness)) == quoteBefore, "quote moved");
            require(harness.marker() == markerBefore, "storage mutated");
        }

        function _args() private view returns (bytes memory) {
            return _argsWith(
                address(series), address(quote), address(oracle), INITIAL_INVENTORY, GAMMA, SPREAD
            );
        }

        function _argsWith(
            address callToken,
            address quoteToken,
            address spotOracle,
            uint256 initialInventory,
            uint256 gammaWad,
            uint256 halfSpreadWad
        ) private pure returns (bytes memory) {
            return abi.encode(
                callToken, quoteToken, spotOracle, initialInventory, gammaWad, halfSpreadWad
            );
        }

        function _expectHealthyBuyRevert(bytes memory args, bytes4 selector) private {
            _expectRevert(
                args,
                address(quote),
                address(series),
                false,
                5_000e6,
                INITIAL_INVENTORY,
                FAIR_QUOTE,
                ONE_CALL,
                selector
            );
        }

        function _expectRevert(
            bytes memory args,
            address tokenIn,
            address tokenOut,
            bool isExactIn,
            uint256 balanceIn,
            uint256 balanceOut,
            uint256 amountIn,
            uint256 amountOut,
            bytes4 selector
        ) private {
            (bool success, bytes memory reason) = address(harness)
                .call(
                    abi.encodeCall(
                        AquaVolInventorySkewHarness.run,
                        (
                            args,
                            tokenIn,
                            tokenOut,
                            isExactIn,
                            balanceIn,
                            balanceOut,
                            amountIn,
                            amountOut
                        )
                    )
                );
            require(!success, "expected revert");
            _requireSelector(reason, selector);
        }

        function _expectBuildRevert(
            address callToken,
            address quoteToken,
            address spotOracle,
            uint256 initialInventory,
            uint256 gammaWad,
            uint256 halfSpreadWad,
            bytes4 selector
        ) private view {
            (bool success, bytes memory reason) = address(harness)
                .staticcall(
                    abi.encodeCall(
                        AquaVolInventorySkewHarness.build,
                        (
                            callToken,
                            quoteToken,
                            spotOracle,
                            initialInventory,
                            gammaWad,
                            halfSpreadWad
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
