// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";

import { AquaVolBaseSepoliaStrategy } from "../src/deployment/AquaVolBaseSepoliaStrategy.sol";
import { UniswapV3TwapOracle } from "../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import { OptionSeries } from "../src/options/OptionSeries.sol";
import { AquaVolSwapVMRouter } from "../src/swapvm/AquaVolSwapVMRouter.sol";
import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";

interface VerificationVm {
    function envAddress(string calldata name) external view returns (address value);
}

interface VerificationToken {
    function balanceOf(address account) external view returns (uint256);
}

/// @notice Read-only verification of the deployed market, settlement, and next quote.
contract VerifyBaseSepoliaDeployment {
    VerificationVm private constant VM =
        VerificationVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant CHAIN_ID = 84_532;
    address private constant OPERATOR = 0xA4A103c574a9bF22Bc49a7Ce3f089508300320d5;
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant AQUA = 0x170B0d7C534785eAD9Ecbc278B3D87781855D4F9;
    address private constant PRICING_ENGINE = 0x68b7036ae9e1266675f226F36d2c764927C84884;
    address private constant ROUTER = 0x8b734D9222D51Aa75C038AB81145FC86D5b4ceb4;
    address private constant ORACLE = 0x2D2bfade5AD73C946fdcA2a882A21E542A568903;
    address private constant SERIES = 0x7F3c414aEf81CAf377fF34A419EC388105fBA117;
    bytes32 private constant STRATEGY_HASH =
        0x1a38d471dce4c9cc7a425010f584dd7ebaf5e0bbcdb42a67506dac1d91e465f5;

    uint256 private constant TRADE_CALL = 0.01e18;
    uint256 private constant MAXIMUM_INPUT = 1e6;
    uint256 private constant EXPECTED_SUPPLY = 0.1e18;
    uint256 private constant EXPECTED_VIRTUAL_CALL = 0.09e18;
    uint256 private constant EXPECTED_VIRTUAL_QUOTE = 50_779_818;
    uint256 private constant EXPECTED_TRADER_CALL = 0.01e18;
    uint256 private constant EXPECTED_TRADER_QUOTE = 4_220_182;

    error VerificationFailed();

    function run()
        external
        view
        returns (uint256 spotPriceWad, uint256 nextAsk, uint256 virtualCall, uint256 virtualQuote)
    {
        address trader = VM.envAddress("TRADER_ADDRESS");
        Aqua aqua = Aqua(AQUA);
        AquaVolSwapVMRouter router = AquaVolSwapVMRouter(payable(ROUTER));
        UniswapV3TwapOracle oracle = UniswapV3TwapOracle(ORACLE);
        OptionSeries series = OptionSeries(SERIES);
        AquaVolDemoUSDC quote = AquaVolDemoUSDC(DEMO_USDC);

        if (
            block.chainid != CHAIN_ID || trader == address(0) || trader == OPERATOR
                || AQUA.code.length != 2_678 || PRICING_ENGINE.code.length != 11_201
                || ROUTER.code.length != 22_503 || address(router.AQUA()) != AQUA
                || address(router.PRICING_ENGINE()) != PRICING_ENGINE
                || address(router.WETH()) != WETH || series.totalSupply() != EXPECTED_SUPPLY
                || VerificationToken(WETH).balanceOf(SERIES) != EXPECTED_SUPPLY
                || series.balanceOf(trader) != EXPECTED_TRADER_CALL
                || quote.balanceOf(trader) != EXPECTED_TRADER_QUOTE
        ) revert VerificationFailed();

        ISwapVM.Order memory order = AquaVolBaseSepoliaStrategy.buildOrder(OPERATOR, SERIES, ORACLE);
        if (router.hash(order) != STRATEGY_HASH) revert VerificationFailed();
        (virtualCall, virtualQuote) =
            aqua.safeBalances(OPERATOR, ROUTER, STRATEGY_HASH, SERIES, DEMO_USDC);
        if (virtualCall != EXPECTED_VIRTUAL_CALL || virtualQuote != EXPECTED_VIRTUAL_QUOTE) {
            revert VerificationFailed();
        }

        spotPriceWad = oracle.read().priceWad;
        uint256 callOutput;
        bytes32 quotedHash;
        (nextAsk, callOutput, quotedHash) = router.asView()
            .quote(
                order,
                TRADE_CALL,
                AquaVolBaseSepoliaStrategy.buildExactOutputBuy(
                    trader, SERIES, MAXIMUM_INPUT, block.timestamp + 5 minutes
                )
            );
        if (
            nextAsk <= 779_818 || nextAsk > MAXIMUM_INPUT || callOutput != TRADE_CALL
                || quotedHash != STRATEGY_HASH
        ) revert VerificationFailed();
    }
}
