// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseSepoliaConfig } from "../../src/deployment/BaseSepoliaConfig.sol";
import { BaseSepoliaPreflight } from "../../src/deployment/BaseSepoliaPreflight.sol";

interface PreflightTestVm {
    function chainId(uint256 newChainId) external;

    function deal(address account, uint256 newBalance) external;
}

contract MockDeploymentFactory {
    int24 public tickSpacing;

    constructor(int24 tickSpacing_) {
        tickSpacing = tickSpacing_;
    }

    function feeAmountTickSpacing(uint24) external view returns (int24) {
        return tickSpacing;
    }
}

contract MockDeploymentPeriphery {
    address public factory;
    address public WETH9;

    constructor(address factory_, address weth_) {
        factory = factory_;
        WETH9 = weth_;
    }
}

contract MockDeploymentWeth {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract BaseSepoliaPreflightHarness {
    function validate(
        address operator,
        uint256 minimumOperatorBalance,
        BaseSepoliaConfig.ExternalContracts calldata contracts_
    ) external view returns (BaseSepoliaPreflight.Report memory) {
        return BaseSepoliaPreflight.validate(operator, minimumOperatorBalance, contracts_);
    }

    function validateManifest(address operator, address trader, bytes20 sourceCommit)
        external
        pure
    {
        BaseSepoliaConfig.validateManifestInputs(operator, trader, sourceCommit);
    }

    function officialContracts()
        external
        pure
        returns (BaseSepoliaConfig.ExternalContracts memory)
    {
        return BaseSepoliaConfig.officialContracts();
    }
}

contract BaseSepoliaPreflightTest {
    PreflightTestVm private constant VM =
        PreflightTestVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant MINIMUM_BALANCE = 0.01 ether;
    address private constant OPERATOR = address(0xA11CE);
    address private constant TRADER = address(0xB0B);
    bytes20 private constant SOURCE_COMMIT = bytes20(uint160(1));

    BaseSepoliaPreflightHarness private harness;

    function setUp() public {
        harness = new BaseSepoliaPreflightHarness();
        VM.chainId(BaseSepoliaConfig.CHAIN_ID);
        VM.deal(OPERATOR, MINIMUM_BALANCE);
    }

    function testOfficialConfigurationIsPinned() public view {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = harness.officialContracts();

        require(BaseSepoliaConfig.CHAIN_ID == 84_532, "wrong chain ID");
        require(BaseSepoliaConfig.POOL_FEE == 3_000, "wrong fee");
        require(BaseSepoliaConfig.POOL_TICK_SPACING == 60, "wrong tick spacing");
        require(BaseSepoliaConfig.TWAP_WINDOW == 30 minutes, "wrong TWAP window");
        require(contracts_.factory == 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24, "factory");
        require(
            contracts_.positionManager == 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2,
            "position manager"
        );
        require(contracts_.swapRouter == 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4, "swap router");
        require(contracts_.weth == 0x4200000000000000000000000000000000000006, "WETH");
    }

    function testValidProfileReturnsIdentityEvidence() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 60);
        BaseSepoliaPreflight.Report memory report =
            harness.validate(OPERATOR, MINIMUM_BALANCE, contracts_);

        require(report.chainId == BaseSepoliaConfig.CHAIN_ID, "report chain");
        require(report.operator == OPERATOR, "report operator");
        require(report.operatorBalance == MINIMUM_BALANCE, "report balance");
        require(report.poolTickSpacing == 60, "report tick spacing");
        require(report.factoryCodehash == contracts_.factory.codehash, "factory hash");
        require(
            report.positionManagerCodehash == contracts_.positionManager.codehash, "manager hash"
        );
        require(report.swapRouterCodehash == contracts_.swapRouter.codehash, "router hash");
        require(report.wethCodehash == contracts_.weth.codehash, "WETH hash");
    }

    function testRejectsWrongChain() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 60);
        VM.chainId(1);
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.WrongChain.selector
        );
    }

    function testRejectsZeroOperatorAndLowBalance() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 60);
        _expectError(
            abi.encodeCall(harness.validate, (address(0), MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.ZeroOperator.selector
        );

        VM.deal(OPERATOR, MINIMUM_BALANCE - 1);
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.OperatorBalanceTooLow.selector
        );
    }

    function testRejectsMissingDependencyCode() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 60);
        contracts_.positionManager = address(0xDEAD);
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.MissingCode.selector
        );
    }

    function testRejectsWrongFeeTierConfiguration() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 10);
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.WrongPoolTickSpacing.selector
        );
    }

    function testRejectsWrongPositionManagerFactory() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 60);
        contracts_.positionManager =
            address(new MockDeploymentPeriphery(address(0xBAD), contracts_.weth));
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.WrongFactoryBinding.selector
        );
    }

    function testRejectsWrongRouterWeth() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(18, 60);
        contracts_.swapRouter =
            address(new MockDeploymentPeriphery(contracts_.factory, address(0xBAD)));
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.WrongWethBinding.selector
        );
    }

    function testRejectsWrongWethDecimals() public {
        BaseSepoliaConfig.ExternalContracts memory contracts_ = _validContracts(6, 60);
        _expectError(
            abi.encodeCall(harness.validate, (OPERATOR, MINIMUM_BALANCE, contracts_)),
            BaseSepoliaPreflight.WrongWethDecimals.selector
        );
    }

    function testManifestRequiresSeparatedNonzeroIdentitiesAndSourceCommit() public {
        harness.validateManifest(OPERATOR, TRADER, SOURCE_COMMIT);

        _expectError(
            abi.encodeCall(harness.validateManifest, (address(0), TRADER, SOURCE_COMMIT)),
            BaseSepoliaConfig.ZeroOperator.selector
        );
        _expectError(
            abi.encodeCall(harness.validateManifest, (OPERATOR, address(0), SOURCE_COMMIT)),
            BaseSepoliaConfig.ZeroTrader.selector
        );
        _expectError(
            abi.encodeCall(harness.validateManifest, (OPERATOR, OPERATOR, SOURCE_COMMIT)),
            BaseSepoliaConfig.RolesNotSeparated.selector
        );
        _expectError(
            abi.encodeCall(harness.validateManifest, (OPERATOR, TRADER, bytes20(0))),
            BaseSepoliaConfig.MissingSourceCommit.selector
        );
    }

    function _validContracts(uint8 wethDecimals, int24 tickSpacing)
        private
        returns (BaseSepoliaConfig.ExternalContracts memory contracts_)
    {
        MockDeploymentFactory factory = new MockDeploymentFactory(tickSpacing);
        MockDeploymentWeth weth = new MockDeploymentWeth(wethDecimals);
        MockDeploymentPeriphery positionManager =
            new MockDeploymentPeriphery(address(factory), address(weth));
        MockDeploymentPeriphery swapRouter =
            new MockDeploymentPeriphery(address(factory), address(weth));

        contracts_ = BaseSepoliaConfig.ExternalContracts({
            factory: address(factory),
            positionManager: address(positionManager),
            swapRouter: address(swapRouter),
            weth: address(weth)
        });
    }

    function _expectError(bytes memory callData, bytes4 expected) private {
        (bool ok, bytes memory reason) = address(harness).call(callData);
        require(!ok, "expected revert");
        require(reason.length >= 4, "missing revert selector");
        bytes4 actual;
        assembly ("memory-safe") {
            actual := mload(add(reason, 0x20))
        }
        require(actual == expected, "wrong revert selector");
    }
}
