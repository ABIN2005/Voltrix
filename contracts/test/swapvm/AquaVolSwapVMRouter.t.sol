// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol custom-router unit tests updated 2026-09-26.

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { AquaOpcodes } from "@1inch/swap-vm/contracts/opcodes/AquaOpcodes.sol";
import { Opcode } from "@1inch/swap-vm/contracts/libs/OpcodeList.sol";
import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { AquaVolInstructionBuilder } from "../../src/swapvm/AquaVolInstructionBuilder.sol";
import { AquaVolOpcode } from "../../src/swapvm/AquaVolOpcode.sol";
import { AquaVolOpcodes } from "../../src/swapvm/AquaVolOpcodes.sol";
import { AquaVolPricingEngine } from "../../src/swapvm/AquaVolPricingEngine.sol";
import { AquaVolSwapVMRouter } from "../../src/swapvm/AquaVolSwapVMRouter.sol";

contract AquaVolBuilderHarness {
    function buildRaw(uint8 opcode, bytes memory args) external pure returns (bytes memory) {
        return AquaVolInstructionBuilder.build(opcode, args);
    }
}

contract AquaVolOpcodeHarness is AquaVolOpcodes {
    constructor(address pricingEngine) AquaVolOpcodes(pricingEngine) { }

    function run(
        uint256 opcode,
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
        _runOpcode(ctx, opcode, args);
        return (ctx.swap.amountIn, ctx.swap.amountOut);
    }
}

contract AquaVolSwapVMRouterTest {
    AquaVolBuilderHarness private builder;
    AquaVolOpcodeHarness private opcodes;
    MockERC20 private callToken;
    MockERC20 private quoteToken;

    function setUp() public {
        builder = new AquaVolBuilderHarness();
        opcodes = new AquaVolOpcodeHarness(address(new AquaVolPricingEngine()));
        callToken = new MockERC20("AquaVol Call", "avCALL", 18);
        quoteToken = new MockERC20("USD Coin", "USDC", 6);
    }

    function testCanonicalActiveOpcodeMapping() public pure {
        require(AquaVolOpcode.OPTION_FAIR_VALUE == 0xd1, "fair-value opcode drift");
        require(AquaVolOpcode.OPTION_INVENTORY_SKEW == 0xd2, "inventory opcode drift");
        require(AquaVolOpcode.RESERVED_BANK_START == 0xf0, "reserved bank drift");
    }

    function testBuilderRejectsArgumentsThatDoNotFitHeader() public {
        bytes memory oversized = new bytes(256);
        (bool success, bytes memory result) = address(builder)
            .call(
                abi.encodeCall(
                    AquaVolBuilderHarness.buildRaw, (AquaVolOpcode.OPTION_FAIR_VALUE, oversized)
                )
            );

        require(!success, "oversized arguments accepted");
        _requireSelector(result, AquaVolInstructionBuilder.ArgumentsTooLong.selector);
    }

    function testUpstreamOpcodeDelegatesWithoutChangingRegisters() public {
        (uint256 amountIn, uint256 amountOut) = opcodes.run(
            uint8(Opcode.Salt),
            hex"1234",
            address(quoteToken),
            address(callToken),
            false,
            7,
            9,
            11,
            13
        );

        require(amountIn == 11, "delegated input changed");
        require(amountOut == 13, "delegated output changed");
    }

    function testRetiredReservedAndUnknownOpcodesDelegateToUpstreamRevert() public {
        _requireUnknownOpcode(0xd0);
        _requireUnknownOpcode(AquaVolOpcode.RESERVED_BANK_START);
        _requireUnknownOpcode(0xef);
    }

    function testRouterPreservesOfficialBindings() public {
        Aqua aqua = new Aqua();
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        AquaVolPricingEngine pricingEngine = new AquaVolPricingEngine();
        AquaVolSwapVMRouter router = new AquaVolSwapVMRouter(
            address(aqua),
            address(weth),
            address(this),
            address(pricingEngine),
            "AquaVol SwapVM",
            "1"
        );

        require(address(router.AQUA()) == address(aqua), "wrong Aqua binding");
        require(address(router.WETH()) == address(weth), "wrong WETH binding");
        require(address(router.PRICING_ENGINE()) == address(pricingEngine), "wrong engine binding");
        require(address(router.asView()) == address(router), "wrong simulator binding");
        require(address(router).code.length <= 24_576, "router exceeds EIP-170");
        require(address(pricingEngine).code.length <= 24_576, "engine exceeds EIP-170");
    }

    function _requireUnknownOpcode(uint8 opcode) private {
        (bool success, bytes memory result) = address(opcodes)
            .call(
                abi.encodeCall(
                    AquaVolOpcodeHarness.run,
                    (opcode, bytes(""), address(quoteToken), address(callToken), false, 0, 0, 0, 0)
                )
            );
        require(!success, "unknown opcode succeeded");
        _requireSelector(result, AquaOpcodes.UnknownOpcode.selector);
    }

    function _requireSelector(bytes memory result, bytes4 expected) private pure {
        require(result.length >= 4, "missing revert selector");
        bytes4 actual;
        assembly ("memory-safe") {
            actual := mload(add(result, 0x20))
        }
        require(actual == expected, "wrong revert selector");
    }
}
