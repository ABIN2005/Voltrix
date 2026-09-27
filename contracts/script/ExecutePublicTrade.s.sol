// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol Base Sepolia public-trade evidence added 2026-09-26.

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";

import { AquaVolBaseSepoliaStrategy } from "../src/deployment/AquaVolBaseSepoliaStrategy.sol";
import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { ISwapRouter02Minimal } from "../src/deployment/interfaces/IUniswapV3Deployment.sol";
import { UniswapV3TwapOracle } from "../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import { OptionSeries } from "../src/options/OptionSeries.sol";
import { AquaVolSwapVMRouter } from "../src/swapvm/AquaVolSwapVMRouter.sol";
import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Refreshes the guarded TWAP and settles the bounded distinct-trader demo purchase.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract ExecutePublicTrade is BaseSepoliaBroadcast {
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    address private constant AQUA = 0x170B0d7C534785eAD9Ecbc278B3D87781855D4F9;
    address private constant ROUTER = 0x8b734D9222D51Aa75C038AB81145FC86D5b4ceb4;
    address private constant ORACLE = 0x2D2bfade5AD73C946fdcA2a882A21E542A568903;
    address private constant SERIES = 0x7F3c414aEf81CAf377fF34A419EC388105fBA117;
    bytes32 private constant STRATEGY_HASH =
        0x1a38d471dce4c9cc7a425010f584dd7ebaf5e0bbcdb42a67506dac1d91e465f5;

    uint256 private constant OBSERVATION_QUOTE_IN = 1e6;
    uint256 private constant MINIMUM_WETH_OUT = 0.0002 ether;
    uint256 private constant TRADE_CALL_OUT = 0.01e18;
    uint256 private constant MAXIMUM_TRADE_INPUT = 1e6;
    uint256 private constant INITIAL_CALL = 0.1e18;
    uint256 private constant INITIAL_QUOTE = 50e6;

    error InvalidTrader(address trader);
    error TraderKeyMismatch(address derived, address expected);
    error UnexpectedPreTradeState();

    event PublicTradeEvidence(
        address indexed trader,
        bytes32 indexed strategyHash,
        uint256 avUsdPaid,
        uint256 callReceived,
        uint256 nextAsk,
        uint256 virtualCallAfter,
        uint256 virtualQuoteAfter
    );

    function run() external returns (uint256 avUsdPaid, uint256 callReceived, uint256 nextAsk) {
        (address operator, uint256 operatorKey) = _prepareBroadcast();
        address trader = VM.envAddress("TRADER_ADDRESS");
        uint256 traderKey = VM.envUint("TRADER_PRIVATE_KEY");
        if (trader == address(0) || trader == operator) revert InvalidTrader(trader);
        address derivedTrader = VM.addr(traderKey);
        if (derivedTrader != trader) revert TraderKeyMismatch(derivedTrader, trader);

        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();
        Aqua aqua = Aqua(AQUA);
        AquaVolSwapVMRouter router = AquaVolSwapVMRouter(payable(ROUTER));
        UniswapV3TwapOracle oracle = UniswapV3TwapOracle(ORACLE);
        OptionSeries series = OptionSeries(SERIES);
        AquaVolDemoUSDC quote = AquaVolDemoUSDC(DEMO_USDC);
        ISwapVM.Order memory order = AquaVolBaseSepoliaStrategy.buildOrder(operator, SERIES, ORACLE);
        if (router.hash(order) != STRATEGY_HASH) revert UnexpectedPreTradeState();

        (uint256 virtualCallBefore, uint256 virtualQuoteBefore) =
            aqua.safeBalances(operator, ROUTER, STRATEGY_HASH, SERIES, DEMO_USDC);
        uint256 traderQuoteBefore = quote.balanceOf(trader);
        uint256 makerQuoteBefore = quote.balanceOf(operator);
        if (
            virtualCallBefore != INITIAL_CALL || virtualQuoteBefore != INITIAL_QUOTE
                || series.balanceOf(trader) != 0 || traderQuoteBefore < MAXIMUM_TRADE_INPUT
                || series.totalSupply() != INITIAL_CALL
                || IERC20Balance(externalContracts.weth).balanceOf(SERIES) != INITIAL_CALL
        ) revert UnexpectedPreTradeState();

        VM.startBroadcast(operatorKey);
        require(
            quote.approve(externalContracts.swapRouter, OBSERVATION_QUOTE_IN),
            "observation approval failed"
        );
        uint256 observationWethOut = ISwapRouter02Minimal(externalContracts.swapRouter)
            .exactInputSingle(
                ISwapRouter02Minimal.ExactInputSingleParams({
                    tokenIn: DEMO_USDC,
                    tokenOut: externalContracts.weth,
                    fee: BaseSepoliaConfig.POOL_FEE,
                    recipient: operator,
                    amountIn: OBSERVATION_QUOTE_IN,
                    amountOutMinimum: MINIMUM_WETH_OUT,
                    sqrtPriceLimitX96: 0
                })
            );
        VM.stopBroadcast();
        require(observationWethOut >= MINIMUM_WETH_OUT, "observation output too low");
        oracle.read();

        bytes memory takerData = AquaVolBaseSepoliaStrategy.buildExactOutputBuy(
            trader, SERIES, MAXIMUM_TRADE_INPUT, block.timestamp + 5 minutes
        );
        (uint256 quotedInput, uint256 quotedOutput, bytes32 quotedHash) =
            router.asView().quote(order, TRADE_CALL_OUT, takerData);
        require(quotedInput <= MAXIMUM_TRADE_INPUT, "quote exceeds maximum");
        require(quotedOutput == TRADE_CALL_OUT, "quote output mismatch");
        require(quotedHash == STRATEGY_HASH, "quote hash mismatch");

        VM.startBroadcast(traderKey);
        require(quote.approve(ROUTER, MAXIMUM_TRADE_INPUT), "trader approval failed");
        bytes32 settledHash;
        (avUsdPaid, callReceived, settledHash) = router.swap(order, TRADE_CALL_OUT, takerData);
        VM.stopBroadcast();

        require(settledHash == STRATEGY_HASH, "settled hash mismatch");
        require(avUsdPaid <= MAXIMUM_TRADE_INPUT, "settlement exceeds maximum");
        require(callReceived == TRADE_CALL_OUT, "settled CALL mismatch");
        require(quote.balanceOf(trader) == traderQuoteBefore - avUsdPaid, "trader quote mismatch");
        require(series.balanceOf(trader) == TRADE_CALL_OUT, "trader CALL mismatch");
        require(
            quote.balanceOf(operator) == makerQuoteBefore - OBSERVATION_QUOTE_IN + avUsdPaid,
            "maker quote mismatch"
        );
        require(
            IERC20Balance(externalContracts.weth).balanceOf(SERIES) == INITIAL_CALL,
            "collateral moved"
        );

        (uint256 virtualCallAfter, uint256 virtualQuoteAfter) =
            aqua.safeBalances(operator, ROUTER, STRATEGY_HASH, SERIES, DEMO_USDC);
        require(virtualCallAfter == INITIAL_CALL - TRADE_CALL_OUT, "virtual CALL mismatch");
        require(virtualQuoteAfter == INITIAL_QUOTE + avUsdPaid, "virtual quote mismatch");
        (nextAsk,,) = router.asView().quote(order, TRADE_CALL_OUT, takerData);
        require(nextAsk > avUsdPaid, "inventory did not reprice");

        emit PublicTradeEvidence(
            trader,
            STRATEGY_HASH,
            avUsdPaid,
            callReceived,
            nextAsk,
            virtualCallAfter,
            virtualQuoteAfter
        );
    }
}

interface IERC20Balance {
    function balanceOf(address account) external view returns (uint256);
}
