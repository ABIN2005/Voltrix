// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IERC20DecimalsMinimal } from "../oracles/uniswap/interfaces/IUniswapV3Minimal.sol";
import {
    IUniswapV3FactoryDeployment,
    IUniswapV3PeripheryIdentity
} from "./interfaces/IUniswapV3Deployment.sol";
import { BaseSepoliaConfig } from "./BaseSepoliaConfig.sol";

/// @notice Read-only validation performed before any AquaVol Base Sepolia transaction.
library BaseSepoliaPreflight {
    bytes32 internal constant FACTORY_LABEL = keccak256("UNISWAP_V3_FACTORY");
    bytes32 internal constant POSITION_MANAGER_LABEL = keccak256("POSITION_MANAGER");
    bytes32 internal constant SWAP_ROUTER_LABEL = keccak256("SWAP_ROUTER_02");
    bytes32 internal constant WETH_LABEL = keccak256("WETH");

    struct Report {
        uint256 chainId;
        address operator;
        uint256 operatorBalance;
        bytes32 factoryCodehash;
        bytes32 positionManagerCodehash;
        bytes32 swapRouterCodehash;
        bytes32 wethCodehash;
        int24 poolTickSpacing;
    }

    error WrongChain(uint256 actual, uint256 expected);
    error ZeroOperator();
    error OperatorBalanceTooLow(uint256 actual, uint256 required);
    error MissingCode(bytes32 dependency, address account);
    error WrongPoolTickSpacing(int24 actual, int24 expected);
    error WrongFactoryBinding(bytes32 dependency, address actual, address expected);
    error WrongWethBinding(bytes32 dependency, address actual, address expected);
    error WrongWethDecimals(uint8 actual, uint8 expected);

    function validate(
        address operator,
        uint256 minimumOperatorBalance,
        BaseSepoliaConfig.ExternalContracts memory contracts_
    ) internal view returns (Report memory report) {
        if (block.chainid != BaseSepoliaConfig.CHAIN_ID) {
            revert WrongChain(block.chainid, BaseSepoliaConfig.CHAIN_ID);
        }
        if (operator == address(0)) revert ZeroOperator();
        if (operator.balance < minimumOperatorBalance) {
            revert OperatorBalanceTooLow(operator.balance, minimumOperatorBalance);
        }

        _requireCode(FACTORY_LABEL, contracts_.factory);
        _requireCode(POSITION_MANAGER_LABEL, contracts_.positionManager);
        _requireCode(SWAP_ROUTER_LABEL, contracts_.swapRouter);
        _requireCode(WETH_LABEL, contracts_.weth);

        int24 tickSpacing = IUniswapV3FactoryDeployment(contracts_.factory)
            .feeAmountTickSpacing(BaseSepoliaConfig.POOL_FEE);
        if (tickSpacing != BaseSepoliaConfig.POOL_TICK_SPACING) {
            revert WrongPoolTickSpacing(tickSpacing, BaseSepoliaConfig.POOL_TICK_SPACING);
        }

        _requirePeripheryBindings(
            POSITION_MANAGER_LABEL, contracts_.positionManager, contracts_.factory, contracts_.weth
        );
        _requirePeripheryBindings(
            SWAP_ROUTER_LABEL, contracts_.swapRouter, contracts_.factory, contracts_.weth
        );

        uint8 wethDecimals = IERC20DecimalsMinimal(contracts_.weth).decimals();
        if (wethDecimals != 18) revert WrongWethDecimals(wethDecimals, 18);

        report = Report({
            chainId: block.chainid,
            operator: operator,
            operatorBalance: operator.balance,
            factoryCodehash: contracts_.factory.codehash,
            positionManagerCodehash: contracts_.positionManager.codehash,
            swapRouterCodehash: contracts_.swapRouter.codehash,
            wethCodehash: contracts_.weth.codehash,
            poolTickSpacing: tickSpacing
        });
    }

    function _requireCode(bytes32 dependency, address account) private view {
        if (account.code.length == 0) revert MissingCode(dependency, account);
    }

    function _requirePeripheryBindings(
        bytes32 dependency,
        address periphery,
        address expectedFactory,
        address expectedWeth
    ) private view {
        address actualFactory = IUniswapV3PeripheryIdentity(periphery).factory();
        if (actualFactory != expectedFactory) {
            revert WrongFactoryBinding(dependency, actualFactory, expectedFactory);
        }

        address actualWeth = IUniswapV3PeripheryIdentity(periphery).WETH9();
        if (actualWeth != expectedWeth) {
            revert WrongWethBinding(dependency, actualWeth, expectedWeth);
        }
    }
}
