// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol Base Sepolia position preparation added 2026-09-26.

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";

import { AquaVolBaseSepoliaStrategy } from "../src/deployment/AquaVolBaseSepoliaStrategy.sol";
import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { IWETH9Minimal } from "../src/deployment/interfaces/IUniswapV3Deployment.sol";
import { VolatilityRegistry } from "../src/oracles/VolatilityRegistry.sol";
import { UniswapV3TwapOracle } from "../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import { OptionSeries } from "../src/options/OptionSeries.sol";
import { AquaVolSwapVMRouter } from "../src/swapvm/AquaVolSwapVMRouter.sol";
import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Stage 6 writes and ships the reviewed covered-call position.
/// @dev ORACLE_ADDRESS and OPTION_SERIES_ADDRESS are public inputs. Running without
///      Forge's --broadcast flag performs a simulation only.
contract PrepareAquaVolPosition is BaseSepoliaBroadcast {
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    address private constant AQUA = 0x170B0d7C534785eAD9Ecbc278B3D87781855D4F9;
    address private constant PRICING_ENGINE = 0x68b7036ae9e1266675f226F36d2c764927C84884;
    address private constant ROUTER = 0x8b734D9222D51Aa75C038AB81145FC86D5b4ceb4;
    address private constant VOLATILITY_REGISTRY = 0xF2537463ddeA54EEa205bD183a9e303bDe02C37e;

    uint256 private constant INITIAL_CALL = 0.1e18;
    uint256 private constant INITIAL_QUOTE = 50e6;
    uint256 private constant DEMO_QUOTE_CALL = 0.01e18;
    uint256 private constant VOLATILITY_WAD = 0.64e18;

    error UnexpectedDeployment();
    error PositionAlreadyPrepared();
    error InsufficientAssetBalance(address token, uint256 actual, uint256 required);

    event AquaVolPositionPrepared(
        address indexed series,
        address indexed oracle,
        bytes32 indexed strategyHash,
        uint256 callInventory,
        uint256 quoteInventory,
        uint256 initialDemoAsk
    );

    function run() external returns (bytes32 strategyHash, uint256 initialDemoAsk) {
        (address operator, uint256 privateKey) = _prepareBroadcast();
        address oracleAddress = VM.envAddress("ORACLE_ADDRESS");
        address seriesAddress = VM.envAddress("OPTION_SERIES_ADDRESS");
        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();

        Aqua aqua = Aqua(AQUA);
        AquaVolSwapVMRouter router = AquaVolSwapVMRouter(payable(ROUTER));
        VolatilityRegistry registry = VolatilityRegistry(VOLATILITY_REGISTRY);
        UniswapV3TwapOracle oracle = UniswapV3TwapOracle(oracleAddress);
        OptionSeries series = OptionSeries(seriesAddress);
        AquaVolDemoUSDC quote = AquaVolDemoUSDC(DEMO_USDC);
        IWETH9Minimal weth = IWETH9Minimal(externalContracts.weth);

        if (
            oracleAddress.code.length == 0 || seriesAddress.code.length == 0
                || address(router.AQUA()) != AQUA
                || address(router.PRICING_ENGINE()) != PRICING_ENGINE
                || address(router.WETH()) != externalContracts.weth
                || registry.UPDATER() != operator || oracle.BASE_TOKEN() != externalContracts.weth
                || oracle.QUOTE_TOKEN() != DEMO_USDC || series.writer() != operator
                || series.underlying() != externalContracts.weth || series.quoteAsset() != DEMO_USDC
                || series.strikePriceWad() != 4_000e18
        ) revert UnexpectedDeployment();
        if (series.totalWritten() != 0 || series.totalSupply() != 0) {
            revert PositionAlreadyPrepared();
        }
        if (weth.balanceOf(operator) < INITIAL_CALL) {
            revert InsufficientAssetBalance(
                externalContracts.weth, weth.balanceOf(operator), INITIAL_CALL
            );
        }
        if (quote.balanceOf(operator) < INITIAL_QUOTE) {
            revert InsufficientAssetBalance(DEMO_USDC, quote.balanceOf(operator), INITIAL_QUOTE);
        }

        oracle.read();
        ISwapVM.Order memory order =
            AquaVolBaseSepoliaStrategy.buildOrder(operator, seriesAddress, oracleAddress);
        (address tokenA, address tokenB) = AquaVolBaseSepoliaStrategy.sortedTokens(seriesAddress);
        address[] memory tokens = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        amounts[0] = tokenA == seriesAddress ? INITIAL_CALL : INITIAL_QUOTE;
        amounts[1] = tokenB == seriesAddress ? INITIAL_CALL : INITIAL_QUOTE;

        VM.startBroadcast(privateKey);
        registry.setVolatility(seriesAddress, VOLATILITY_WAD);
        require(weth.approve(seriesAddress, INITIAL_CALL), "WETH approval failed");
        series.write(INITIAL_CALL);
        require(series.approve(AQUA, INITIAL_CALL), "CALL approval failed");
        require(quote.approve(AQUA, INITIAL_QUOTE), "quote approval failed");
        strategyHash = aqua.ship(ROUTER, abi.encode(order), tokens, amounts);
        VM.stopBroadcast();

        require(strategyHash == router.hash(order), "strategy hash mismatch");
        require(series.balanceOf(operator) == INITIAL_CALL, "CALL balance mismatch");
        require(weth.balanceOf(seriesAddress) == INITIAL_CALL, "collateral mismatch");
        (uint256 virtualCall, uint256 virtualQuote) =
            aqua.safeBalances(operator, ROUTER, strategyHash, seriesAddress, DEMO_USDC);
        require(virtualCall == INITIAL_CALL, "virtual CALL mismatch");
        require(virtualQuote == INITIAL_QUOTE, "virtual quote mismatch");

        (initialDemoAsk,,) = router.asView()
            .quote(
                order,
                DEMO_QUOTE_CALL,
                AquaVolBaseSepoliaStrategy.buildExactOutputBuy(
                    operator, seriesAddress, 1e6, block.timestamp + 5 minutes
                )
            );
        emit AquaVolPositionPrepared(
            seriesAddress, oracleAddress, strategyHash, INITIAL_CALL, INITIAL_QUOTE, initialDemoAsk
        );
    }
}
