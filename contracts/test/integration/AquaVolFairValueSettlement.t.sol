// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol fair-value settlement tests added 2026-09-26.

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
import { AquaVolFairValue } from "../../src/swapvm/AquaVolFairValue.sol";
import { AquaVolSwapVMRouter } from "../../src/swapvm/AquaVolSwapVMRouter.sol";
import { AquaVolPricingEngine } from "../../src/swapvm/AquaVolPricingEngine.sol";
import { MockUniswapV3Factory, MockUniswapV3Pool } from "../oracles/mocks/MockUniswapV3.sol";

interface FairValueSettlementVm {
    function prank(address sender) external;
    function startPrank(address sender) external;
    function stopPrank() external;
    function warp(uint256 newTimestamp) external;
}

/// @notice End-to-end Aqua settlement evidence for strategy-bound fair value.
contract AquaVolFairValueSettlementTest {
    FairValueSettlementVm private constant VM =
        FairValueSettlementVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant NOW = 1_000_000;
    uint256 private constant INITIAL_CALL = 10e18;
    uint256 private constant INITIAL_USDC = 5_000e6;
    uint256 private constant TRADE_CALL = 1e18 + 1;
    uint256 private constant STRIKE = 4_000e18;
    uint256 private constant VOLATILITY = 0.64e18;
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

    function testExactOutputBuyQuoteAndSwapReconcileThroughAqua() public {
        uint256 expectedUsdc = FullMath.mulDivUp(TRADE_CALL, premiumWad, QUOTE_SCALE);
        (uint256 quotedUsdc, uint256 quotedCall, bytes32 quotedHash) = router.asView()
            .quote(order, TRADE_CALL, _takerData(false, address(usdc), 0, block.timestamp + 60));
        require(quotedUsdc == expectedUsdc, "wrong fair-value buy quote");
        require(quotedCall == TRADE_CALL, "wrong CALL buy quote");
        require(quotedHash == strategyHash, "wrong buy strategy hash");

        usdc.mint(address(taker), quotedUsdc);
        (uint256 paidUsdc, uint256 receivedCall) = taker.swap(
            order, TRADE_CALL, _takerData(false, address(usdc), quotedUsdc, block.timestamp + 60)
        );

        require(paidUsdc == quotedUsdc, "buy quote/swap input differ");
        require(receivedCall == quotedCall, "buy quote/swap output differ");
        require(usdc.balanceOf(address(taker)) == 0, "trader USDC after buy");
        require(series.balanceOf(address(taker)) == TRADE_CALL, "trader CALL after buy");
        require(usdc.balanceOf(WRITER) == INITIAL_USDC + paidUsdc, "maker USDC after buy");
        require(series.balanceOf(WRITER) == INITIAL_CALL - receivedCall, "maker CALL after buy");

        (uint256 virtualCall, uint256 virtualUsdc) = _virtualBalances();
        require(virtualCall == INITIAL_CALL - receivedCall, "virtual CALL after buy");
        require(virtualUsdc == INITIAL_USDC + paidUsdc, "virtual USDC after buy");
        _requireCollateralUnchanged();
    }

    function testExactInputSellBackQuoteAndSwapReconcileThroughAqua() public {
        uint256 expectedUsdc = FullMath.mulDiv(TRADE_CALL, premiumWad, QUOTE_SCALE);
        VM.prank(WRITER);
        require(series.transfer(address(taker), TRADE_CALL), "CALL funding failed");

        (uint256 quotedCall, uint256 quotedUsdc, bytes32 quotedHash) = router.asView()
            .quote(order, TRADE_CALL, _takerData(true, address(series), 0, block.timestamp + 60));
        require(quotedCall == TRADE_CALL, "wrong CALL sell quote");
        require(quotedUsdc == expectedUsdc, "wrong fair-value sell quote");
        require(quotedHash == strategyHash, "wrong sell strategy hash");

        (uint256 paidCall, uint256 receivedUsdc) = taker.swap(
            order, TRADE_CALL, _takerData(true, address(series), quotedUsdc, block.timestamp + 60)
        );

        require(paidCall == quotedCall, "sell quote/swap input differ");
        require(receivedUsdc == quotedUsdc, "sell quote/swap output differ");
        require(series.balanceOf(address(taker)) == 0, "trader CALL after sell");
        require(usdc.balanceOf(address(taker)) == receivedUsdc, "trader USDC after sell");
        require(series.balanceOf(WRITER) == INITIAL_CALL, "maker CALL after sell");
        require(usdc.balanceOf(WRITER) == INITIAL_USDC - receivedUsdc, "maker USDC after sell");

        (uint256 virtualCall, uint256 virtualUsdc) = _virtualBalances();
        require(virtualCall == INITIAL_CALL + paidCall, "virtual CALL after sell");
        require(virtualUsdc == INITIAL_USDC - receivedUsdc, "virtual USDC after sell");
        _requireCollateralUnchanged();
    }

    function testAlteredFairValueStrategyCannotUseShippedBalances() public {
        ISwapVM.Order memory alteredOrder = order;
        alteredOrder.data = bytes.concat(order.data, hex"00");
        usdc.mint(address(taker), INITIAL_USDC);

        bool didRevert;
        try taker.swap(
            alteredOrder,
            TRADE_CALL,
            _takerData(false, address(usdc), INITIAL_USDC, block.timestamp + 60)
        ) { }
        catch {
            didRevert = true;
        }
        require(didRevert, "altered strategy executed");
        require(series.balanceOf(address(taker)) == 0, "altered strategy sent CALL");
        (uint256 virtualCall, uint256 virtualUsdc) = _virtualBalances();
        require(virtualCall == INITIAL_CALL, "altered virtual CALL");
        require(virtualUsdc == INITIAL_USDC, "altered virtual USDC");
    }

    function testGuardedOracleFailureStopsQuote() public {
        pool.setLatestObservation(uint32(NOW - ORACLE_MAX_AGE - 1), true);
        bool didRevert;
        try router.asView()
            .quote(order, TRADE_CALL, _takerData(false, address(usdc), 0, block.timestamp + 60)) { }
        catch {
            didRevert = true;
        }
        require(didRevert, "stale oracle quote succeeded");
    }

    function _buildOrder() private view returns (ISwapVM.Order memory) {
        bytes memory program = bytes.concat(
            AquaVolFairValue.build(
                address(series), address(usdc), address(oracle), address(registry), 1 hours
            ),
            Salt.build(uint64(3))
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

    function _virtualBalances() private view returns (uint256 callBalance, uint256 usdcBalance) {
        return
            aqua.safeBalances(WRITER, address(router), strategyHash, address(series), address(usdc));
    }

    function _requireCollateralUnchanged() private view {
        require(weth.balanceOf(address(series)) == INITIAL_CALL, "collateral moved");
        require(weth.balanceOf(address(series)) == series.totalSupply(), "backing changed");
    }
}
