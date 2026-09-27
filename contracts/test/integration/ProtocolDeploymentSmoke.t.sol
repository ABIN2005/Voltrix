// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { Aqua } from "@1inch/aqua/src/Aqua.sol";
import { AquaSwapVMRouter } from "@1inch/swap-vm/contracts/routers/AquaSwapVMRouter.sol";

import { MockERC20 } from "../../src/mocks/MockERC20.sol";

/// @notice Deployment-only proof for the pinned, unmodified protocol contracts.
/// @dev Aqua — © Degensoft Ltd 2025. SwapVM — © Degensoft Ltd 2025.
contract ProtocolDeploymentSmokeTest {
    function testDeploysAndBindsPinnedProtocolContracts() public {
        Aqua aqua = new Aqua();
        MockERC20 weth = new MockERC20("Wrapped Ether", "WETH", 18);
        AquaSwapVMRouter router = new AquaSwapVMRouter(
            address(aqua), address(weth), address(this), "AquaVol SwapVM", "1"
        );

        require(address(router.AQUA()) == address(aqua), "wrong Aqua binding");
        require(address(router.WETH()) == address(weth), "wrong WETH binding");
        require(address(router.asView()) == address(router), "wrong view interface");
    }
}
