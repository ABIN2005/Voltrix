// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { VolatilityRegistry } from "../../src/oracles/VolatilityRegistry.sol";

interface VolatilityVm {
    function expectEmit(
        bool checkTopic1,
        bool checkTopic2,
        bool checkTopic3,
        bool checkData,
        address emitter
    ) external;

    function warp(uint256 newTimestamp) external;
}

contract MockVolatilitySeries { }

contract RevertingVolatilitySeries {
    fallback() external {
        revert("registry must not call series");
    }
}

contract VolatilityRegistryCaller {
    function update(VolatilityRegistry registry, address series, uint256 volatilityWad) external {
        registry.setVolatility(series, volatilityWad);
    }
}

contract VolatilityRegistryTest {
    VolatilityVm private constant VM =
        VolatilityVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant MIN_VOLATILITY = 0.0001e18;
    uint256 private constant MAX_VOLATILITY = 5e18;
    uint256 private constant INITIAL_VOLATILITY = 0.64e18;
    uint64 private constant INITIAL_TIME = 1_000_000;

    VolatilityRegistry private registry;
    MockVolatilitySeries private series;

    event VolatilityUpdated(
        address indexed series,
        uint256 previousVolatilityWad,
        uint256 newVolatilityWad,
        uint64 updatedAt
    );

    function setUp() public {
        VM.warp(INITIAL_TIME);
        registry = new VolatilityRegistry(address(this));
        series = new MockVolatilitySeries();
    }

    function testBindsImmutableUpdaterAndBounds() public view {
        require(registry.UPDATER() == address(this), "wrong updater");
        require(registry.MIN_VOLATILITY_WAD() == MIN_VOLATILITY, "wrong minimum");
        require(registry.MAX_VOLATILITY_WAD() == MAX_VOLATILITY, "wrong maximum");
    }

    function testConstructorRejectsZeroUpdater() public {
        try new VolatilityRegistry(address(0)) returns (VolatilityRegistry) {
            revert("constructor succeeded");
        } catch (bytes memory reason) {
            _requireSelector(reason, VolatilityRegistry.InvalidUpdater.selector);
        }
    }

    function testUnconfiguredSeriesReadsAsZero() public view {
        (uint256 volatilityWad, uint64 updatedAt) = registry.read(address(series));
        require(volatilityWad == 0, "unexpected volatility");
        require(updatedAt == 0, "unexpected timestamp");
    }

    function testUpdaterStoresTimestampAndEmitsChange() public {
        VM.expectEmit(true, false, false, true, address(registry));
        emit VolatilityUpdated(address(series), 0, INITIAL_VOLATILITY, INITIAL_TIME);

        registry.setVolatility(address(series), INITIAL_VOLATILITY);

        (uint256 volatilityWad, uint64 updatedAt) = registry.read(address(series));
        require(volatilityWad == INITIAL_VOLATILITY, "wrong volatility");
        require(updatedAt == INITIAL_TIME, "wrong timestamp");
    }

    function testSameValueRefreshesTimestampAndReportsPreviousValue() public {
        registry.setVolatility(address(series), INITIAL_VOLATILITY);
        uint64 refreshedAt = INITIAL_TIME + 300;
        VM.warp(refreshedAt);

        VM.expectEmit(true, false, false, true, address(registry));
        emit VolatilityUpdated(address(series), INITIAL_VOLATILITY, INITIAL_VOLATILITY, refreshedAt);
        registry.setVolatility(address(series), INITIAL_VOLATILITY);

        (uint256 volatilityWad, uint64 updatedAt) = registry.read(address(series));
        require(volatilityWad == INITIAL_VOLATILITY, "volatility changed");
        require(updatedAt == refreshedAt, "timestamp not refreshed");
    }

    function testRejectsUnauthorizedUpdater() public {
        VolatilityRegistryCaller caller = new VolatilityRegistryCaller();
        (bool success, bytes memory reason) = address(caller)
            .call(
                abi.encodeCall(
                    VolatilityRegistryCaller.update, (registry, address(series), INITIAL_VOLATILITY)
                )
            );
        require(!success, "unauthorized update succeeded");
        _requireSelector(reason, VolatilityRegistry.UnauthorizedUpdater.selector);

        (uint256 volatilityWad, uint64 updatedAt) = registry.read(address(series));
        require(volatilityWad == 0 && updatedAt == 0, "record mutated");
    }

    function testRejectsSeriesWithoutCode() public {
        _expectUpdateRevert(
            address(0x1234), INITIAL_VOLATILITY, VolatilityRegistry.SeriesHasNoCode.selector
        );
    }

    function testOnlyInspectsSeriesCodeWithoutCallingIt() public {
        RevertingVolatilitySeries revertingSeries = new RevertingVolatilitySeries();
        registry.setVolatility(address(revertingSeries), INITIAL_VOLATILITY);

        (uint256 volatilityWad, uint64 updatedAt) = registry.read(address(revertingSeries));
        require(volatilityWad == INITIAL_VOLATILITY, "wrong volatility");
        require(updatedAt == INITIAL_TIME, "wrong timestamp");
    }

    function testAcceptsBothVolatilityBounds() public {
        registry.setVolatility(address(series), MIN_VOLATILITY);
        (uint256 minimum,) = registry.read(address(series));
        require(minimum == MIN_VOLATILITY, "minimum rejected");

        registry.setVolatility(address(series), MAX_VOLATILITY);
        (uint256 maximum,) = registry.read(address(series));
        require(maximum == MAX_VOLATILITY, "maximum rejected");
    }

    function testRejectsValuesOutsideBounds() public {
        _expectUpdateRevert(
            address(series), MIN_VOLATILITY - 1, VolatilityRegistry.VolatilityOutOfRange.selector
        );
        _expectUpdateRevert(
            address(series), MAX_VOLATILITY + 1, VolatilityRegistry.VolatilityOutOfRange.selector
        );
    }

    function testRejectsTimestampThatCannotFitRecord() public {
        VM.warp(uint256(type(uint64).max) + 1);
        _expectUpdateRevert(
            address(series), INITIAL_VOLATILITY, VolatilityRegistry.TimestampOverflow.selector
        );

        (uint256 volatilityWad, uint64 updatedAt) = registry.read(address(series));
        require(volatilityWad == 0 && updatedAt == 0, "overflow update mutated record");
    }

    function testFuzzStoresEveryValueInsideBounds(uint128 candidate) public {
        uint256 volatilityWad =
            MIN_VOLATILITY + (uint256(candidate) % (MAX_VOLATILITY - MIN_VOLATILITY + 1));
        registry.setVolatility(address(series), volatilityWad);

        (uint256 stored, uint64 updatedAt) = registry.read(address(series));
        require(stored == volatilityWad, "fuzz value changed");
        require(updatedAt == INITIAL_TIME, "fuzz timestamp");
    }

    function testRecordsRemainIsolatedBySeries() public {
        MockVolatilitySeries secondSeries = new MockVolatilitySeries();
        registry.setVolatility(address(series), INITIAL_VOLATILITY);
        registry.setVolatility(address(secondSeries), 1.25e18);

        (uint256 firstValue, uint64 firstTime) = registry.read(address(series));
        (uint256 secondValue, uint64 secondTime) = registry.read(address(secondSeries));
        require(firstValue == INITIAL_VOLATILITY, "first value changed");
        require(secondValue == 1.25e18, "second value changed");
        require(firstTime == INITIAL_TIME && secondTime == INITIAL_TIME, "wrong times");
    }

    function _expectUpdateRevert(address targetSeries, uint256 value, bytes4 expectedSelector)
        private
    {
        (bool success, bytes memory reason) = address(registry)
            .call(abi.encodeCall(VolatilityRegistry.setVolatility, (targetSeries, value)));
        require(!success, "update succeeded");
        _requireSelector(reason, expectedSelector);
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
