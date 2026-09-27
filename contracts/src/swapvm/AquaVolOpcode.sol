// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol opcode allocation added 2026-09-26.

/// @notice Canonical opcode assignments for AquaVol's pinned SwapVM extension.
library AquaVolOpcode {
    uint8 internal constant OPTION_FAIR_VALUE = 0xd1;
    uint8 internal constant OPTION_INVENTORY_SKEW = 0xd2;
    uint8 internal constant RESERVED_BANK_START = 0xf0;
}
