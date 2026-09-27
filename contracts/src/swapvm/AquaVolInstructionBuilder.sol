// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol raw-opcode builder added 2026-09-26.

/// @notice Builds the two-byte instruction header consumed by the pinned SwapVM.
library AquaVolInstructionBuilder {
    error ArgumentsTooLong(uint256 length);

    function build(uint8 opcode, bytes memory args) internal pure returns (bytes memory) {
        if (args.length >= 256) revert ArgumentsTooLong(args.length);
        return bytes.concat(bytes1(opcode), bytes1(uint8(args.length)), args);
    }
}
