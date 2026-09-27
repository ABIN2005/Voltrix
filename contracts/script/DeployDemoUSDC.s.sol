// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Stage 1 deploys only the capped AquaVol demo quote token.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract DeployDemoUSDC is BaseSepoliaBroadcast {
    event DemoUSDCDeployment(address indexed token, address indexed minter, uint256 supplyCap);

    function run() external returns (AquaVolDemoUSDC token) {
        (address operator, uint256 privateKey) = _prepareBroadcast();

        VM.startBroadcast(privateKey);
        token = new AquaVolDemoUSDC(operator);
        VM.stopBroadcast();

        require(token.minter() == operator, "wrong token minter");
        require(token.decimals() == 6, "wrong token decimals");
        require(token.totalSupply() == 0, "unexpected initial supply");
        emit DemoUSDCDeployment(address(token), operator, token.MAX_SUPPLY());
    }
}
