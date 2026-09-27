// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { InventoryPricing } from "../../src/pricing/InventoryPricing.sol";

interface InventoryPricingVm {
    function parseJsonString(string calldata json, string calldata key)
        external
        pure
        returns (string memory value);

    function readFile(string calldata path) external view returns (string memory data);
}

contract InventoryPricingHarness {
    function buy(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) external pure returns (InventoryPricing.Result memory) {
        return InventoryPricing.buy(
            fairValueQuote, initialInventory, currentInventory, quantity, gammaWad, halfSpreadWad
        );
    }

    function sell(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) external pure returns (InventoryPricing.Result memory) {
        return InventoryPricing.sell(
            fairValueQuote, initialInventory, currentInventory, quantity, gammaWad, halfSpreadWad
        );
    }
}

contract InventoryPricingTest {
    InventoryPricingVm private constant VM =
        InventoryPricingVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant WAD = 1e18;
    uint256 private constant ONE_CALL = 1e18;
    uint256 private constant INITIAL_INVENTORY = 10e18;
    uint256 private constant FAIR_QUOTE = 60_294_027;
    uint256 private constant GAMMA = 0.2e18;
    uint256 private constant SPREAD = 0.01e18;

    InventoryPricingHarness private harness;
    string private vectors;

    function setUp() public {
        harness = new InventoryPricingHarness();
        vectors = VM.readFile("../test/vectors/inventory_settlement-v1.json");
    }

    function testConsumesAllCommittedIntegerVectorsExactly() public view {
        for (uint256 i = 0; i < 8; ++i) {
            string memory prefix = string.concat(".cases[", _toString(i), "]");
            string memory side = VM.parseJsonString(vectors, string.concat(prefix, ".side"));
            uint256 fairValueQuote = _vectorUint(prefix, ".inputs.fair_value_quote");
            uint256 initialInventory = _vectorUint(prefix, ".inputs.initial_inventory");
            uint256 currentInventory = _vectorUint(prefix, ".inputs.current_inventory");
            uint256 quantity = _vectorUint(prefix, ".inputs.quantity");
            uint256 gammaWad = _vectorUint(prefix, ".inputs.gamma_wad");
            uint256 halfSpreadWad = _vectorUint(prefix, ".inputs.half_spread_wad");

            InventoryPricing.Result memory result;
            if (keccak256(bytes(side)) == keccak256("buy")) {
                result = harness.buy(
                    fairValueQuote,
                    initialInventory,
                    currentInventory,
                    quantity,
                    gammaWad,
                    halfSpreadWad
                );
            } else {
                require(keccak256(bytes(side)) == keccak256("sell"), "unknown side");
                result = harness.sell(
                    fairValueQuote,
                    initialInventory,
                    currentInventory,
                    quantity,
                    gammaWad,
                    halfSpreadWad
                );
            }

            require(
                result.inventoryAfter == _vectorUint(prefix, ".expected.inventory_after"),
                "inventory after"
            );
            require(
                result.averageExposureWad == _vectorUint(prefix, ".expected.average_exposure_wad"),
                "average exposure"
            );
            require(
                result.inventoryFactorWad == _vectorUint(prefix, ".expected.inventory_factor_wad"),
                "inventory factor"
            );
            require(
                result.reservationQuote == _vectorUint(prefix, ".expected.reservation_quote"),
                "reservation quote"
            );
            require(
                result.finalQuote == _vectorUint(prefix, ".expected.final_quote"), "final quote"
            );
        }
    }

    function testCanonicalBuyRoundsUpAtBothStages() public view {
        InventoryPricing.Result memory result =
            harness.buy(FAIR_QUOTE, INITIAL_INVENTORY, INITIAL_INVENTORY, ONE_CALL, GAMMA, SPREAD);

        require(result.averageExposureWad == 0.05e18, "average exposure");
        require(result.inventoryFactorWad == 1.01e18, "factor");
        require(result.reservationQuote == 60_896_968, "reservation rounding");
        require(result.finalQuote == 61_505_938, "spread rounding");
    }

    function testSellRoundsDownAtBothStages() public view {
        InventoryPricing.Result memory result =
            harness.sell(FAIR_QUOTE, INITIAL_INVENTORY, 5e18, ONE_CALL, GAMMA, SPREAD);

        require(result.inventoryAfter == 6e18, "inventory after");
        require(result.averageExposureWad == 0.45e18, "average exposure");
        require(result.reservationQuote == 65_720_489, "reservation rounding");
        require(result.finalQuote == 65_063_284, "spread rounding");
    }

    function testBlockAndSequentialExecutionStayInsideBudget() public view {
        InventoryPricing.Result memory blockQuote = harness.buy(
            5 * FAIR_QUOTE, INITIAL_INVENTORY, INITIAL_INVENTORY, 5 * ONE_CALL, GAMMA, SPREAD
        );

        uint256 currentInventory = INITIAL_INVENTORY;
        uint256 sequentialTotal;
        for (uint256 i = 0; i < 5; ++i) {
            InventoryPricing.Result memory quote = harness.buy(
                FAIR_QUOTE, INITIAL_INVENTORY, currentInventory, ONE_CALL, GAMMA, SPREAD
            );
            sequentialTotal += quote.finalQuote;
            currentInventory = quote.inventoryAfter;
        }

        require(_absoluteDifference(blockQuote.finalQuote, sequentialTotal) <= 18, "split budget");
    }

    function testLaterBuyAndLargerBuyDoNotReceiveBetterPricing() public view {
        InventoryPricing.Result memory first =
            harness.buy(FAIR_QUOTE, INITIAL_INVENTORY, 10e18, ONE_CALL, GAMMA, SPREAD);
        InventoryPricing.Result memory later =
            harness.buy(FAIR_QUOTE, INITIAL_INVENTORY, 9e18, ONE_CALL, GAMMA, SPREAD);
        InventoryPricing.Result memory twoCalls =
            harness.buy(2 * FAIR_QUOTE, INITIAL_INVENTORY, 10e18, 2e18, GAMMA, SPREAD);

        require(later.finalQuote > first.finalQuote, "later ask not higher");
        require(twoCalls.finalQuote >= 2 * first.finalQuote, "larger average ask improved");
    }

    function testAcceptsExactParameterBoundaries() public view {
        InventoryPricing.Result memory minimum = harness.buy(1, 1, 1, 1, 0, 0);
        require(minimum.finalQuote == 1, "minimum");

        InventoryPricing.Result memory maximum =
            harness.sell(2, type(uint128).max, 0, type(uint128).max, WAD, 0.25e18);
        require(maximum.inventoryAfter == type(uint128).max, "maximum transition");
        require(maximum.finalQuote != 0, "maximum quote");
    }

    function testRejectsOneUnitOutsideStaticDomains() public view {
        _expectBuyRevert(
            0,
            INITIAL_INVENTORY,
            INITIAL_INVENTORY,
            ONE_CALL,
            GAMMA,
            SPREAD,
            InventoryPricing.ZeroFairValueQuote.selector
        );
        _expectBuyRevert(1, 0, 0, 1, 0, 0, InventoryPricing.InitialInventoryOutsideDomain.selector);
        _expectBuyRevert(
            1,
            uint256(type(uint128).max) + 1,
            1,
            1,
            0,
            0,
            InventoryPricing.InitialInventoryOutsideDomain.selector
        );
        _expectBuyRevert(
            FAIR_QUOTE,
            INITIAL_INVENTORY,
            INITIAL_INVENTORY + 1,
            ONE_CALL,
            GAMMA,
            SPREAD,
            InventoryPricing.CurrentInventoryOutsideDomain.selector
        );
        _expectBuyRevert(
            FAIR_QUOTE,
            INITIAL_INVENTORY,
            INITIAL_INVENTORY,
            0,
            GAMMA,
            SPREAD,
            InventoryPricing.ZeroQuantity.selector
        );
        _expectBuyRevert(
            FAIR_QUOTE,
            INITIAL_INVENTORY,
            INITIAL_INVENTORY,
            ONE_CALL,
            WAD + 1,
            SPREAD,
            InventoryPricing.GammaOutsideDomain.selector
        );
        _expectBuyRevert(
            FAIR_QUOTE,
            INITIAL_INVENTORY,
            INITIAL_INVENTORY,
            ONE_CALL,
            GAMMA,
            0.25e18 + 1,
            InventoryPricing.HalfSpreadOutsideDomain.selector
        );
    }

    function testRejectsBuyAndSellOutsideInventory() public view {
        _expectBuyRevert(
            FAIR_QUOTE,
            INITIAL_INVENTORY,
            ONE_CALL,
            ONE_CALL + 1,
            GAMMA,
            SPREAD,
            InventoryPricing.InventoryTransitionOutsideDomain.selector
        );
        _expectSellRevert(
            FAIR_QUOTE,
            INITIAL_INVENTORY,
            INITIAL_INVENTORY,
            1,
            GAMMA,
            SPREAD,
            InventoryPricing.InventoryTransitionOutsideDomain.selector
        );
    }

    function testRejectsSellResultThatRoundsToZero() public view {
        _expectSellRevert(1, 2, 1, 1, 0, 0.25e18, InventoryPricing.ZeroFinalQuote.selector);
    }

    function testFuzzLaterInventoryNeverLowersBuyQuote(uint64 quantitySeed, uint64 inventorySeed)
        public
        view
    {
        uint256 quantity = 1 + uint256(quantitySeed) % ONE_CALL;
        uint256 laterInventory =
            quantity + uint256(inventorySeed) % (INITIAL_INVENTORY - quantity + 1);

        InventoryPricing.Result memory initial = harness.buy(
            FAIR_QUOTE, INITIAL_INVENTORY, INITIAL_INVENTORY, quantity, GAMMA, SPREAD
        );
        InventoryPricing.Result memory later =
            harness.buy(FAIR_QUOTE, INITIAL_INVENTORY, laterInventory, quantity, GAMMA, SPREAD);
        require(later.finalQuote >= initial.finalQuote, "non-monotonic buy quote");
    }

    function _vectorUint(string memory prefix, string memory suffix)
        private
        view
        returns (uint256)
    {
        return _parseUint(VM.parseJsonString(vectors, string.concat(prefix, suffix)));
    }

    function _expectBuyRevert(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad,
        bytes4 expectedSelector
    ) private view {
        (bool success, bytes memory reason) = address(harness)
            .staticcall(
                abi.encodeCall(
                    InventoryPricingHarness.buy,
                    (
                        fairValueQuote,
                        initialInventory,
                        currentInventory,
                        quantity,
                        gammaWad,
                        halfSpreadWad
                    )
                )
            );
        require(!success, "buy succeeded");
        _requireSelector(reason, expectedSelector);
    }

    function _expectSellRevert(
        uint256 fairValueQuote,
        uint256 initialInventory,
        uint256 currentInventory,
        uint256 quantity,
        uint256 gammaWad,
        uint256 halfSpreadWad,
        bytes4 expectedSelector
    ) private view {
        (bool success, bytes memory reason) = address(harness)
            .staticcall(
                abi.encodeCall(
                    InventoryPricingHarness.sell,
                    (
                        fairValueQuote,
                        initialInventory,
                        currentInventory,
                        quantity,
                        gammaWad,
                        halfSpreadWad
                    )
                )
            );
        require(!success, "sell succeeded");
        _requireSelector(reason, expectedSelector);
    }

    function _parseUint(string memory value) private pure returns (uint256 result) {
        bytes memory characters = bytes(value);
        require(characters.length != 0, "empty integer");
        for (uint256 i = 0; i < characters.length; ++i) {
            uint8 character = uint8(characters[i]);
            require(character >= 48 && character <= 57, "invalid integer");
            result = result * 10 + character - 48;
        }
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temporary = value;
        uint256 digits;
        while (temporary != 0) {
            ++digits;
            temporary /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            --digits;
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }

    function _absoluteDifference(uint256 a, uint256 b) private pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _requireSelector(bytes memory reason, bytes4 expectedSelector) private pure {
        require(reason.length >= 4, "missing revert selector");
        bytes4 actualSelector;
        assembly ("memory-safe") {
            actualSelector := mload(add(reason, 0x20))
        }
        require(actualSelector == expectedSelector, "wrong revert selector");
    }
}
