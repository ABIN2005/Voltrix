// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { FullMath } from "../libraries/FullMath.sol";

/// @notice Storage-free inventory and spread adjustment for USDC-native option quotes.
library InventoryPricing {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_INITIAL_INVENTORY = type(uint128).max;
    uint256 internal constant MAX_GAMMA_WAD = 1e18;
    uint256 internal constant MAX_HALF_SPREAD_WAD = 0.25e18;

    struct Result {
        uint256 inventoryAfter;
        uint256 averageExposureWad;
        uint256 inventoryFactorWad;
        uint256 reservationQuote;
        uint256 finalQuote;
    }

    error ZeroFairValueQuote();
    error InitialInventoryOutsideDomain(uint256 initialInventory);
    error CurrentInventoryOutsideDomain(uint256 currentInventory, uint256 initialInventory);
    error ZeroQuantity();
    error InventoryTransitionOutsideDomain(
        uint256 currentInventory, uint256 quantity, uint256 initialInventory
    );
    error GammaOutsideDomain(uint256 gammaWad);
    error HalfSpreadOutsideDomain(uint256 halfSpreadWad);
    error ZeroFinalQuote();

    function buy(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) internal pure returns (Result memory result) {
        _validateCommon(
            fairValueQuote, initialInventory, currentInventory, quantity, gammaWad, halfSpreadWad
        );
        if (quantity > currentInventory) {
            revert InventoryTransitionOutsideDomain(currentInventory, quantity, initialInventory);
        }

        result.inventoryAfter = currentInventory - quantity;
        (result.averageExposureWad, result.inventoryFactorWad) =
            _inventoryFactor(initialInventory, currentInventory, result.inventoryAfter, gammaWad);
        result.reservationQuote = FullMath.mulDivUp(fairValueQuote, result.inventoryFactorWad, WAD);
        result.finalQuote = FullMath.mulDivUp(result.reservationQuote, WAD + halfSpreadWad, WAD);
    }

    function sell(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) internal pure returns (Result memory result) {
        _validateCommon(
            fairValueQuote, initialInventory, currentInventory, quantity, gammaWad, halfSpreadWad
        );
        if (quantity > initialInventory - currentInventory) {
            revert InventoryTransitionOutsideDomain(currentInventory, quantity, initialInventory);
        }

        result.inventoryAfter = currentInventory + quantity;
        (result.averageExposureWad, result.inventoryFactorWad) =
            _inventoryFactor(initialInventory, currentInventory, result.inventoryAfter, gammaWad);
        result.reservationQuote = FullMath.mulDiv(fairValueQuote, result.inventoryFactorWad, WAD);
        result.finalQuote = FullMath.mulDiv(result.reservationQuote, WAD - halfSpreadWad, WAD);
        if (result.finalQuote == 0) revert ZeroFinalQuote();
    }

    function _inventoryFactor(
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 inventoryAfter,
        uint256 gammaWad
    ) private pure returns (uint256 averageExposureWad, uint256 inventoryFactorWad) {
        uint256 soldBefore = initialInventory - currentInventory;
        uint256 soldAfter = initialInventory - inventoryAfter;
        averageExposureWad = FullMath.mulDiv(soldBefore + soldAfter, WAD, 2 * initialInventory);
        inventoryFactorWad = WAD + FullMath.mulDiv(gammaWad, averageExposureWad, WAD);
    }

    function _validateCommon(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) private pure {
        if (fairValueQuote == 0) revert ZeroFairValueQuote();
        if (initialInventory == 0 || initialInventory > MAX_INITIAL_INVENTORY) {
            revert InitialInventoryOutsideDomain(initialInventory);
        }
        if (currentInventory > initialInventory) {
            revert CurrentInventoryOutsideDomain(currentInventory, initialInventory);
        }
        if (quantity == 0) revert ZeroQuantity();
        if (gammaWad > MAX_GAMMA_WAD) revert GammaOutsideDomain(gammaWad);
        if (halfSpreadWad > MAX_HALF_SPREAD_WAD) {
            revert HalfSpreadOutsideDomain(halfSpreadWad);
        }
    }
}
