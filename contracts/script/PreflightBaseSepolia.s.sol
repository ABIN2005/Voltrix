// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { BaseSepoliaPreflight } from "../src/deployment/BaseSepoliaPreflight.sol";

interface PreflightVm {
    function envAddress(string calldata name) external view returns (address value);

    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256 value);
}

/// @notice Read-only Base Sepolia dependency and operator check.
/// @dev This script has no broadcast call and never reads PRIVATE_KEY.
contract PreflightBaseSepolia {
    PreflightVm private constant VM =
        PreflightVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event PreflightIdentity(uint256 chainId, address indexed operator, uint256 operatorBalance);
    event PreflightDependency(
        bytes32 indexed dependency, address indexed account, bytes32 codehash
    );
    event PreflightPoolFee(uint24 fee, int24 tickSpacing);

    function run() external returns (BaseSepoliaPreflight.Report memory report) {
        address operator = VM.envAddress("OPERATOR_ADDRESS");
        uint256 minimumBalance =
            VM.envOr("MIN_OPERATOR_BALANCE_WEI", BaseSepoliaConfig.DEFAULT_MIN_OPERATOR_BALANCE);
        BaseSepoliaConfig.ExternalContracts memory contracts_ =
            BaseSepoliaConfig.officialContracts();

        report = BaseSepoliaPreflight.validate(operator, minimumBalance, contracts_);

        emit PreflightIdentity(report.chainId, report.operator, report.operatorBalance);
        emit PreflightDependency(
            keccak256("UNISWAP_V3_FACTORY"), contracts_.factory, report.factoryCodehash
        );
        emit PreflightDependency(
            keccak256("POSITION_MANAGER"),
            contracts_.positionManager,
            report.positionManagerCodehash
        );
        emit PreflightDependency(
            keccak256("SWAP_ROUTER_02"), contracts_.swapRouter, report.swapRouterCodehash
        );
        emit PreflightDependency(keccak256("WETH"), contracts_.weth, report.wethCodehash);
        emit PreflightPoolFee(BaseSepoliaConfig.POOL_FEE, report.poolTickSpacing);
    }
}
