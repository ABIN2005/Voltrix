// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { AquaVolFairValue } from "./AquaVolFairValue.sol";
import { AquaVolInventorySkew } from "./AquaVolInventorySkew.sol";
import { AquaVolOpcode } from "./AquaVolOpcode.sol";
import { IAquaVolPricingEngine } from "./IAquaVolPricingEngine.sol";

/// @notice Isolates AquaVol's computation-heavy pricing from the size-constrained SwapVM router.
/// @dev The engine is stateless. It can only read strategy-bound inputs and return updated registers;
///      Aqua and SwapVM remain the sole token-settlement path.
contract AquaVolPricingEngine is IAquaVolPricingEngine {
    error UnsupportedOpcode(uint256 opcode);

    function execute(uint256 opcode, bytes calldata args, Registers calldata registers)
        external
        view
        returns (uint256 amountIn, uint256 amountOut)
    {
        Context memory ctx;
        ctx.query.tokenIn = registers.tokenIn;
        ctx.query.tokenOut = registers.tokenOut;
        ctx.query.isExactIn = registers.isExactIn;
        ctx.swap.balanceIn = registers.balanceIn;
        ctx.swap.balanceOut = registers.balanceOut;
        ctx.swap.amountIn = registers.amountIn;
        ctx.swap.amountOut = registers.amountOut;

        if (opcode == AquaVolOpcode.OPTION_FAIR_VALUE) {
            AquaVolFairValue.exec(ctx, args);
        } else if (opcode == AquaVolOpcode.OPTION_INVENTORY_SKEW) {
            AquaVolInventorySkew.exec(ctx, args);
        } else {
            revert UnsupportedOpcode(opcode);
        }

        return (ctx.swap.amountIn, ctx.swap.amountOut);
    }
}
