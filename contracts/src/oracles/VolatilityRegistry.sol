// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IVolatilityRegistry } from "./interfaces/IVolatilityRegistry.sol";

/// @notice Bounded administrator-supplied implied volatility for AquaVol series.
/// @dev The updater is an explicit MVP trust boundary and cannot be replaced.
contract VolatilityRegistry is IVolatilityRegistry {
    uint256 public constant MIN_VOLATILITY_WAD = 0.0001e18;
    uint256 public constant MAX_VOLATILITY_WAD = 5e18;

    address public immutable UPDATER;

    struct Record {
        uint128 volatilityWad;
        uint64 updatedAt;
    }

    mapping(address series => Record record) private _records;

    event VolatilityUpdated(
        address indexed series,
        uint256 previousVolatilityWad,
        uint256 newVolatilityWad,
        uint64 updatedAt
    );

    error InvalidUpdater();
    error UnauthorizedUpdater(address caller);
    error SeriesHasNoCode(address series);
    error VolatilityOutOfRange(uint256 volatilityWad);
    error TimestampOverflow(uint256 timestamp);

    constructor(address updater) {
        if (updater == address(0)) revert InvalidUpdater();
        UPDATER = updater;
    }

    /// @notice Set or refresh the annualized implied volatility for a series.
    function setVolatility(address series, uint256 volatilityWad) external {
        if (msg.sender != UPDATER) revert UnauthorizedUpdater(msg.sender);
        if (series.code.length == 0) revert SeriesHasNoCode(series);
        if (volatilityWad < MIN_VOLATILITY_WAD || volatilityWad > MAX_VOLATILITY_WAD) {
            revert VolatilityOutOfRange(volatilityWad);
        }
        if (block.timestamp > type(uint64).max) revert TimestampOverflow(block.timestamp);

        Record memory previous = _records[series];
        uint64 updatedAt = uint64(block.timestamp);
        _records[series] = Record({ volatilityWad: uint128(volatilityWad), updatedAt: updatedAt });

        emit VolatilityUpdated(series, previous.volatilityWad, volatilityWad, updatedAt);
    }

    /// @inheritdoc IVolatilityRegistry
    function read(address series) external view returns (uint256 volatilityWad, uint64 updatedAt) {
        Record memory record = _records[series];
        return (record.volatilityWad, record.updatedAt);
    }
}
