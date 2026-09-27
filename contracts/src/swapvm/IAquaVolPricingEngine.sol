// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice Read-only execution boundary for AquaVol's custom SwapVM pricing instructions.
interface IAquaVolPricingEngine {
    struct Registers {
        address tokenIn;
        address tokenOut;
        bool isExactIn;
        uint256 balanceIn;
        uint256 balanceOut;
        uint256 amountIn;
        uint256 amountOut;
    }

    function execute(uint256 opcode, bytes calldata args, Registers calldata registers)
        external
        view
        returns (uint256 amountIn, uint256 amountOut);
}
