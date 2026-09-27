// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol router extension added 2026-09-26.

import { Simulator } from "@1inch/solidity-utils/contracts/mixins/Simulator.sol";
import { SwapVM } from "@1inch/swap-vm/contracts/SwapVM.sol";
import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { AquaVolOpcodes } from "./AquaVolOpcodes.sol";

/// @notice Aqua SwapVM router extended with the isolated AquaVol opcode set.
contract AquaVolSwapVMRouter is Simulator, SwapVM, AquaVolOpcodes {
    constructor(
        address aqua,
        address weth,
        address owner,
        address pricingEngine,
        string memory name,
        string memory version
    ) SwapVM(aqua, weth, owner, name, version) AquaVolOpcodes(pricingEngine) { }

    function _dispatch(Context memory ctx, uint256 opcode, bytes calldata args) internal override {
        _runOpcode(ctx, opcode, args);
    }
}
