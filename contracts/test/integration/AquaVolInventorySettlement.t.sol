// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol inventory-aware settlement tests added 2026-09-26.

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";
import { MockTaker } from "@1inch/swap-vm/test/solidity/mocks/MockTaker.sol";

import { FullMath } from "../../src/libraries/FullMath.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { VolatilityRegistry } from "../../src/oracles/VolatilityRegistry.sol";
import { UniswapV3TwapOracle } from "../../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import { OptionSeries } from "../../src/options/OptionSeries.sol";
import { BlackScholes } from "../../src/pricing/BlackScholes.sol";
import { InventoryPricing } from "../../src/pricing/InventoryPricing.sol";
import { AquaVolFairValue } from "../../src/swapvm/AquaVolFairValue.sol";
import { AquaVolInventorySkew } from "../../src/swapvm/AquaVolInventorySkew.sol";
import { AquaVolSwapVMRouter } from "../../src/swapvm/AquaVolSwapVMRouter.sol";
import { AquaVolPricingEngine } from "../../src/swapvm/AquaVolPricingEngine.sol";
import { MockUniswapV3Factory, MockUniswapV3Pool } from "../oracles/mocks/MockUniswapV3.sol";

interface InventorySettlementVm {
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
}

/// @notice End-to-end evidence for immutable strategies that reprice from live Aqua inventory.
contract AquaVolInventorySettlementTest {
    InventorySettlementVm private constant VM =
        InventorySettlementVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant NOW = 1_000_000;
    uint256 private constant INITIAL_CALL = 10e18;
    uint256 private constant INITIAL_USDC = 5_000e6;
    uint256 private constant ONE_CALL = 1e18;
    uint256 private constant STRIKE = 4_000e18;
    uint256 private constant VOLATILITY = 0.64e18;
    uint256 private constant GAMMA = 0.2e18;
    uint256 private constant HALF_SPREAD = 0.01e18;
    uint256 private constant QUOTE_SCALE = 1e30;
    uint24 private constant FEE = 3000;
    uint32 private constant WINDOW = 1800;
    uint32 private constant ORACLE_MAX_AGE = 120;
    uint128 private constant TARGET_LIQUIDITY = 1_000_000_000_000;
    uint24 private constant MAX_TICK_DEVIATION = 500;
    int24 private constant ABSOLUTE_DEMO_TICK = 193892;
    address private constant WRITER = address(0xA11CE);

    Aqua private aqua;
    AquaVolSwapVMRouter private router;
    MockTaker private taker;
    MockERC20 private weth;
    MockERC20 private usdc;
    OptionSeries private series;
    MockUniswapV3Factory private factory;
    MockUniswapV3Pool private pool;
    UniswapV3TwapOracle private oracle;
    VolatilityRegistry private registry;
    ISwapVM.Order private order;
    bytes32 private strategyHash;
    uint256 private premiumWad;

    function setUp() public {
        VM.warp(NOW);
        aqua = new Aqua();
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        AquaVolPricingEngine pricingEngine = new AquaVolPricingEngine();
        router = new AquaVolSwapVMRouter(
            address(aqua),
            address(weth),
            address(this),
            address(pricingEngine),
            "AquaVol SwapVM",
            "1"
        );
        taker = new MockTaker(aqua, router, address(this));

        series = new OptionSeries(
            WRITER,
            address(weth),
            address(usdc),
            STRIKE,
            NOW + 7 days,
            24 hours,
            "AquaVol WETH 4000 Call",
            "avWETH-4000-C"
        );

        factory = new MockUniswapV3Factory();
        pool = new MockUniswapV3Pool(address(weth), address(usdc), FEE);
        factory.setPool(address(weth), address(usdc), FEE, address(pool));
        _configureHealthyPool();
        oracle = new UniswapV3TwapOracle(
            address(factory),
            address(pool),
            address(weth),
            address(usdc),
            FEE,
            WINDOW,
            TARGET_LIQUIDITY / 2,
            ORACLE_MAX_AGE,
            MAX_TICK_DEVIATION
        );
        registry = new VolatilityRegistry(address(this));
        registry.setVolatility(address(series), VOLATILITY);

        weth.mint(WRITER, INITIAL_CALL);
        usdc.mint(WRITER, INITIAL_USDC);
        VM.startPrank(WRITER);
        weth.approve(address(series), type(uint256).max);
        series.write(INITIAL_CALL);
        series.approve(address(aqua), type(uint256).max);
        usdc.approve(address(aqua), type(uint256).max);
        VM.stopPrank();

        order = _buildOrder();
        strategyHash = _ship(order);
        premiumWad = BlackScholes.callPrice(
            oracle.read().priceWad, STRIKE, series.expiry() - block.timestamp, VOLATILITY
        );
    }

    function testSameStrategyRepricesSecondBuyAndReconcilesBalances() public {
        uint256 firstQuote = _quoteBuy(ONE_CALL);
        require(firstQuote == _expectedBuy(INITIAL_CALL, ONE_CALL), "wrong first quote");
        _executeBuy(ONE_CALL, firstQuote);

        uint256 secondQuote = _quoteBuy(ONE_CALL);
        require(
            secondQuote == _expectedBuy(INITIAL_CALL - ONE_CALL, ONE_CALL), "wrong second quote"
        );
        require(secondQuote > firstQuote, "second ask not higher");
        require(router.hash(order) == strategyHash, "strategy changed");
        _executeBuy(ONE_CALL, secondQuote);

        uint256 totalPaid = firstQuote + secondQuote;
        require(usdc.balanceOf(address(taker)) == 0, "trader USDC");
        require(series.balanceOf(address(taker)) == 2 * ONE_CALL, "trader CALL");
        require(usdc.balanceOf(WRITER) == INITIAL_USDC + totalPaid, "maker USDC");
        require(series.balanceOf(WRITER) == INITIAL_CALL - 2 * ONE_CALL, "maker CALL");
        _requireVirtualBalances(INITIAL_CALL - 2 * ONE_CALL, INITIAL_USDC + totalPaid);
        _requireCollateralUnchanged();
    }

    function testBuyThenSellBackRestoresInventoryAndFirstAsk() public {
        uint256 buyQuote = _quoteBuy(ONE_CALL);
        _executeBuy(ONE_CALL, buyQuote);

        uint256 sellQuote = _quoteSell(ONE_CALL);
        require(
            sellQuote == _expectedSell(INITIAL_CALL - ONE_CALL, ONE_CALL), "wrong sell-back quote"
        );
        _executeSell(ONE_CALL, sellQuote);

        require(_quoteBuy(ONE_CALL) == buyQuote, "restored inventory ask changed");
        require(series.balanceOf(address(taker)) == 0, "trader CALL");
        require(usdc.balanceOf(address(taker)) == sellQuote, "trader USDC");
        require(usdc.balanceOf(WRITER) == INITIAL_USDC + buyQuote - sellQuote, "maker USDC");
        require(series.balanceOf(WRITER) == INITIAL_CALL, "maker CALL");
        _requireVirtualBalances(INITIAL_CALL, INITIAL_USDC + buyQuote - sellQuote);
        _requireCollateralUnchanged();
    }

    function testBlockAndSequentialBuysStayInsideNativeUnitBudget() public {
        uint256 fillCount = 5;
        uint256 blockQuote = _quoteBuy(fillCount * ONE_CALL);
        uint256 sequentialTotal;
        uint256 previousQuote;

        for (uint256 i = 0; i < fillCount; ++i) {
            uint256 nextQuote = _quoteBuy(ONE_CALL);
            if (i != 0) require(nextQuote > previousQuote, "sequential ask not higher");
            _executeBuy(ONE_CALL, nextQuote);
            sequentialTotal += nextQuote;
            previousQuote = nextQuote;
        }

        uint256 tolerance = 3 * (fillCount + 1);
        require(
            _absoluteDifference(blockQuote, sequentialTotal) <= tolerance,
            "split execution outside tolerance"
        );
        _requireVirtualBalances(INITIAL_CALL - fillCount * ONE_CALL, INITIAL_USDC + sequentialTotal);
    }

    function testAlteredCompositeStrategyCannotUseShippedBalances() public {
        ISwapVM.Order memory alteredOrder = order;
        alteredOrder.data = bytes.concat(order.data, hex"00");
        usdc.mint(address(taker), INITIAL_USDC);

        bool didRevert;
        try taker.swap(
            alteredOrder,
            ONE_CALL,
            _takerData(false, address(usdc), INITIAL_USDC, block.timestamp + 60)
        ) { }
        catch {
            didRevert = true;
        }
        require(didRevert, "altered strategy executed");
        require(series.balanceOf(address(taker)) == 0, "altered strategy sent CALL");
        _requireVirtualBalances(INITIAL_CALL, INITIAL_USDC);
    }

    function testGuardedOracleFailureStopsCompositeQuote() public {
        pool.setLatestObservation(uint32(NOW - ORACLE_MAX_AGE - 1), true);
        bool didRevert;
        try router.asView()
            .quote(order, ONE_CALL, _takerData(false, address(usdc), 0, block.timestamp + 60)) { }
        catch {
            didRevert = true;
        }
        require(didRevert, "stale oracle quote succeeded");
        _requireVirtualBalances(INITIAL_CALL, INITIAL_USDC);
    }

    function _expectedBuy(uint256 currentInventory, uint256 quantity)
        private
        view
        returns (uint256)
    {
        uint256 fairValueQuote = FullMath.mulDivUp(quantity, premiumWad, QUOTE_SCALE);
        return InventoryPricing.buy(
            fairValueQuote, INITIAL_CALL, currentInventory, quantity, GAMMA, HALF_SPREAD
        )
        .finalQuote;
    }

    function _expectedSell(uint256 currentInventory, uint256 quantity)
        private
        view
        returns (uint256)
    {
        uint256 fairValueQuote = FullMath.mulDiv(quantity, premiumWad, QUOTE_SCALE);
        return InventoryPricing.sell(
            fairValueQuote, INITIAL_CALL, currentInventory, quantity, GAMMA, HALF_SPREAD
        )
        .finalQuote;
    }

    function _quoteBuy(uint256 quantity) private view returns (uint256 quoteAmount) {
        uint256 callAmount;
        bytes32 quotedHash;
        (quoteAmount, callAmount, quotedHash) = router.asView()
            .quote(order, quantity, _takerData(false, address(usdc), 0, block.timestamp + 60));
        require(callAmount == quantity, "buy CALL quote changed");
        require(quotedHash == strategyHash, "wrong buy strategy hash");
    }

    function _quoteSell(uint256 quantity) private view returns (uint256 quoteAmount) {
        uint256 callAmount;
        bytes32 quotedHash;
        (callAmount, quoteAmount, quotedHash) = router.asView()
            .quote(order, quantity, _takerData(true, address(series), 0, block.timestamp + 60));
        require(callAmount == quantity, "sell CALL quote changed");
        require(quotedHash == strategyHash, "wrong sell strategy hash");
    }

    function _executeBuy(uint256 quantity, uint256 expectedQuote) private {
        usdc.mint(address(taker), expectedQuote);
        (uint256 paidUsdc, uint256 receivedCall) = taker.swap(
            order, quantity, _takerData(false, address(usdc), expectedQuote, block.timestamp + 60)
        );
        require(paidUsdc == expectedQuote, "buy quote/swap input differ");
        require(receivedCall == quantity, "buy quote/swap output differ");
    }

    function _executeSell(uint256 quantity, uint256 expectedQuote) private {
        (uint256 paidCall, uint256 receivedUsdc) = taker.swap(
            order, quantity, _takerData(true, address(series), expectedQuote, block.timestamp + 60)
        );
        require(paidCall == quantity, "sell quote/swap input differ");
        require(receivedUsdc == expectedQuote, "sell quote/swap output differ");
    }

    function _buildOrder() private view returns (ISwapVM.Order memory) {
        bytes memory program = bytes.concat(
            AquaVolFairValue.build(
                address(series), address(usdc), address(oracle), address(registry), 1 hours
            ),
            AquaVolInventorySkew.build(
                address(series), address(usdc), address(oracle), INITIAL_CALL, GAMMA, HALF_SPREAD
            ),
            Salt.build(uint64(4))
        );
        (address tokenA, address tokenB) = _sortedTokens();
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: WRITER,
                receiver: address(0),
                tokenA: tokenA,
                tokenB: tokenB,
                shouldUnwrapWeth: false,
                useAquaInsteadOfSignature: true,
                allowZeroAmountIn: false,
                usePermit2: false,
                hasPreTransferInHook: false,
                hasPostTransferInHook: false,
                hasPreTransferOutHook: false,
                hasPostTransferOutHook: false,
                preTransferInTarget: address(0),
                preTransferInData: "",
                postTransferInTarget: address(0),
                postTransferInData: "",
                preTransferOutTarget: address(0),
                preTransferOutData: "",
                postTransferOutTarget: address(0),
                postTransferOutData: "",
                program: program
            })
        );
    }

    function _ship(ISwapVM.Order memory shippedOrder) private returns (bytes32 shippedHash) {
        (address tokenA, address tokenB) = _sortedTokens();
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        amounts[0] = tokenA == address(series) ? INITIAL_CALL : INITIAL_USDC;
        amounts[1] = tokenB == address(series) ? INITIAL_CALL : INITIAL_USDC;

        VM.prank(WRITER);
        shippedHash = aqua.ship(address(router), abi.encode(shippedOrder), tokens, amounts);
        require(shippedHash == router.hash(shippedOrder), "ship/hash bytes differ");
    }

    function _takerData(bool isExactIn, address tokenIn, uint256 threshold, uint256 deadline)
        private
        view
        returns (bytes memory)
    {
        (address tokenA,) = _sortedTokens();
        require(deadline <= type(uint40).max, "deadline overflow");
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: address(taker),
                isExactIn: isExactIn,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: false,
                isAToB: tokenIn == tokenA,
                allowPartialFill: false,
                usePermit2: false,
                threshold: threshold == 0 ? bytes("") : abi.encode(threshold),
                to: address(0),
                // The preceding bound check makes this narrowing conversion safe.
                // forge-lint: disable-next-line(unsafe-typecast)
                deadline: uint40(deadline),
                hasPreTransferInCallback: true,
                hasPreTransferOutCallback: false,
                preTransferInHookData: "",
                postTransferInHookData: "",
                preTransferOutHookData: "",
                postTransferOutHookData: "",
                preTransferInCallbackData: "",
                preTransferOutCallbackData: "",
                instructionsArgs: "",
                signature: ""
            })
        );
    }

    function _configureHealthyPool() private {
        int24 meanTick = address(weth) > address(usdc) ? ABSOLUTE_DEMO_TICK : -ABSOLUTE_DEMO_TICK;
        pool.setSlot0(meanTick, 0, 2);
        pool.setLiquidity(TARGET_LIQUIDITY * 2);
        pool.setLatestObservation(uint32(NOW - 30), true);
        pool.setObservationWindow(
            WINDOW,
            0,
            int56(int256(meanTick) * int256(uint256(WINDOW))),
            0,
            uint160((uint256(WINDOW) * type(uint160).max) / (uint256(TARGET_LIQUIDITY) << 32))
        );
    }

    function _sortedTokens() private view returns (address tokenA, address tokenB) {
        tokenA = address(series);
        tokenB = address(usdc);
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    }

    function _requireVirtualBalances(uint256 callBalance, uint256 usdcBalance) private view {
        (uint256 actualCall, uint256 actualUsdc) =
            aqua.safeBalances(WRITER, address(router), strategyHash, address(series), address(usdc));
        require(actualCall == callBalance, "virtual CALL");
        require(actualUsdc == usdcBalance, "virtual USDC");
    }

    function _requireCollateralUnchanged() private view {
        require(weth.balanceOf(address(series)) == INITIAL_CALL, "collateral moved");
        require(weth.balanceOf(address(series)) == series.totalSupply(), "backing changed");
    }

    function _absoluteDifference(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
