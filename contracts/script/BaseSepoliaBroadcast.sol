// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { BaseSepoliaPreflight } from "../src/deployment/BaseSepoliaPreflight.sol";

interface BroadcastVm {
    function addr(uint256 privateKey) external pure returns (address keyAddr);

    function envAddress(string calldata name) external view returns (address value);

    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256 value);

    function envUint(string calldata name) external view returns (uint256 value);

    function startBroadcast(uint256 privateKey) external;

    function stopBroadcast() external;
}

/// @notice Shared fail-closed identity and network checks for staged Base Sepolia scripts.
abstract contract BaseSepoliaBroadcast {
    BroadcastVm internal constant VM =
        BroadcastVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error EmptyPrivateKey();
    error SignerMismatch(address derived, address expected);

    function _prepareBroadcast() internal view returns (address operator, uint256 privateKey) {
        operator = VM.envAddress("OPERATOR_ADDRESS");
        privateKey = VM.envUint("PRIVATE_KEY");
        if (privateKey == 0) revert EmptyPrivateKey();

        address derived = VM.addr(privateKey);
        if (derived != operator) revert SignerMismatch(derived, operator);

        uint256 minimumBalance =
            VM.envOr("MIN_OPERATOR_BALANCE_WEI", BaseSepoliaConfig.DEFAULT_MIN_OPERATOR_BALANCE);
        BaseSepoliaPreflight.validate(
            operator, minimumBalance, BaseSepoliaConfig.officialContracts()
        );
    }
}
