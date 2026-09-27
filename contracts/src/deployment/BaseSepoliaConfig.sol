// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Reviewed constants and public-manifest identity checks for AquaVol Base Sepolia.
library BaseSepoliaConfig {
    uint256 internal constant CHAIN_ID = 84_532;
    uint24 internal constant POOL_FEE = 3_000;
    int24 internal constant POOL_TICK_SPACING = 60;
    uint32 internal constant TWAP_WINDOW = 30 minutes;
    uint32 internal constant MAX_LATEST_OBSERVATION_AGE = 2 minutes;
    uint256 internal constant DEFAULT_MIN_OPERATOR_BALANCE = 0.01 ether;

    address internal constant UNISWAP_V3_FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address internal constant NONFUNGIBLE_POSITION_MANAGER =
        0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;
    address internal constant SWAP_ROUTER_02 = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    struct ExternalContracts {
        address factory;
        address positionManager;
        address swapRouter;
        address weth;
    }

    error ZeroOperator();
    error ZeroTrader();
    error RolesNotSeparated(address account);
    error MissingSourceCommit();

    function officialContracts() internal pure returns (ExternalContracts memory contracts_) {
        contracts_ = ExternalContracts({
            factory: UNISWAP_V3_FACTORY,
            positionManager: NONFUNGIBLE_POSITION_MANAGER,
            swapRouter: SWAP_ROUTER_02,
            weth: WETH
        });
    }

    function validateManifestInputs(address operator, address trader, bytes20 sourceCommit)
        internal
        pure
    {
        if (operator == address(0)) revert ZeroOperator();
        if (trader == address(0)) revert ZeroTrader();
        if (operator == trader) revert RolesNotSeparated(operator);
        if (sourceCommit == bytes20(0)) revert MissingSourceCommit();
    }
}
