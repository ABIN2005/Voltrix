// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

import { Salt } from "@1inch/swap-vm/contracts/instructions/Controls.sol";
import { ISwapVM } from "@1inch/swap-vm/contracts/interfaces/ISwapVM.sol";
import { MakerTraitsLib } from "@1inch/swap-vm/contracts/libs/MakerTraits.sol";
import { TakerTraitsLib } from "@1inch/swap-vm/contracts/libs/TakerTraits.sol";

import { AquaVolFairValue } from "../swapvm/AquaVolFairValue.sol";
import { AquaVolInventorySkew } from "../swapvm/AquaVolInventorySkew.sol";

/// @notice Single canonical encoder for the deployed Base Sepolia strategy and buy intent.
library AquaVolBaseSepoliaStrategy {
    address internal constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    address internal constant VOLATILITY_REGISTRY = 0xF2537463ddeA54EEa205bD183a9e303bDe02C37e;
    uint256 internal constant INITIAL_CALL = 0.1e18;
    uint256 internal constant INITIAL_QUOTE = 50e6;
    uint256 internal constant MAXIMUM_VOLATILITY_AGE = 1 hours;
    uint256 internal constant GAMMA_WAD = 0.2e18;
    uint256 internal constant HALF_SPREAD_WAD = 0.01e18;

    function buildOrder(address operator, address series, address oracle)
        internal
        pure
        returns (ISwapVM.Order memory)
    {
        bytes memory program = bytes.concat(
            AquaVolFairValue.build(
                series, DEMO_USDC, oracle, VOLATILITY_REGISTRY, MAXIMUM_VOLATILITY_AGE
            ),
            AquaVolInventorySkew.build(
                series, DEMO_USDC, oracle, INITIAL_CALL, GAMMA_WAD, HALF_SPREAD_WAD
            ),
            Salt.build(uint64(4))
        );
        (address tokenA, address tokenB) = sortedTokens(series);
        return MakerTraitsLib.build(
            MakerTraitsLib.Args({
                maker: operator,
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

    function buildExactOutputBuy(
        address taker,
        address series,
        uint256 maximumInput,
        uint256 deadline
    ) internal pure returns (bytes memory) {
        (address tokenA,) = sortedTokens(series);
        return TakerTraitsLib.build(
            TakerTraitsLib.Args({
                taker: taker,
                isExactIn: false,
                shouldUnwrapWeth: false,
                isStrictThresholdAmount: false,
                isFirstTransferFromTaker: false,
                useTransferFromAndAquaPush: true,
                isAToB: DEMO_USDC == tokenA,
                allowPartialFill: false,
                usePermit2: false,
                threshold: abi.encode(maximumInput),
                to: address(0),
                deadline: uint40(deadline),
                hasPreTransferInCallback: false,
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

    function sortedTokens(address series) internal pure returns (address tokenA, address tokenB) {
        tokenA = series;
        tokenB = DEMO_USDC;
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
    }
}
