// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Read interface for annualized implied volatility keyed by option series.
interface IVolatilityRegistry {
    /// @return volatilityWad Annualized implied volatility with 18 decimals.
    /// @return updatedAt Block timestamp of the latest accepted update.
    function read(address series) external view returns (uint256 volatilityWad, uint64 updatedAt);
}
