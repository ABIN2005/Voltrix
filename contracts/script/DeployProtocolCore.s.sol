// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol staged Base Sepolia deployment script added 2026-09-26.

import { Aqua } from "@1inch/aqua/src/Aqua.sol";

import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { VolatilityRegistry } from "../src/oracles/VolatilityRegistry.sol";
import { AquaVolPricingEngine } from "../src/swapvm/AquaVolPricingEngine.sol";
import { AquaVolSwapVMRouter } from "../src/swapvm/AquaVolSwapVMRouter.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Stage 3 deploys exact pinned Aqua and the operator-bound AquaVol core.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract DeployProtocolCore is BaseSepoliaBroadcast {
    event ProtocolCoreDeployment(
        address indexed aqua,
        address indexed router,
        address indexed pricingEngine,
        address volatilityRegistry,
        address operator
    );

    function run()
        external
        returns (
            Aqua aqua,
            AquaVolPricingEngine pricingEngine,
            AquaVolSwapVMRouter router,
            VolatilityRegistry registry
        )
    {
        (address operator, uint256 privateKey) = _prepareBroadcast();
        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();

        VM.startBroadcast(privateKey);
        aqua = new Aqua();
        pricingEngine = new AquaVolPricingEngine();
        router = new AquaVolSwapVMRouter(
            address(aqua),
            externalContracts.weth,
            operator,
            address(pricingEngine),
            "AquaVol SwapVM",
            "1"
        );
        registry = new VolatilityRegistry(operator);
        VM.stopBroadcast();

        require(address(router.AQUA()) == address(aqua), "wrong Aqua binding");
        require(address(router.WETH()) == externalContracts.weth, "wrong WETH binding");
        require(address(router.PRICING_ENGINE()) == address(pricingEngine), "wrong engine binding");
        require(registry.UPDATER() == operator, "wrong updater");
        emit ProtocolCoreDeployment(
            address(aqua), address(router), address(pricingEngine), address(registry), operator
        );
    }
}
