// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.30;

import {
    IERC20DecimalsMinimal,
    IUniswapV3FactoryMinimal,
    IUniswapV3PoolMinimal
} from "../../src/oracles/uniswap/interfaces/IUniswapV3Minimal.sol";
import { UniswapV3OracleMath } from "../../src/oracles/uniswap/UniswapV3OracleMath.sol";

interface BaseSepoliaForkVm {
    function createSelectFork(string calldata urlOrAlias) external returns (uint256 forkId);

    function envOr(string calldata name, bool defaultValue) external view returns (bool value);

    function envString(string calldata name) external view returns (string memory value);
}

/// @notice Opt-in, read-only evidence for the official Base Sepolia V3 deployment.
/// @dev This test performs no broadcast, deployment, pool mutation, liquidity operation, or swap.
/// Enable it explicitly with RUN_BASE_SEPOLIA_FORK=true and BASE_SEPOLIA_RPC_URL.
contract BaseSepoliaUniswapV3ForkTest {
    BaseSepoliaForkVm private constant VM =
        BaseSepoliaForkVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 private constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint24 private constant FEE = 3000;
    uint32 private constant WINDOW = 30 minutes;

    // Official registry/token addresses; the pool itself is always resolved from the factory.
    address private constant FACTORY = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;
    address private constant POSITION_MANAGER = 0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2;
    address private constant SWAP_ROUTER = 0x94cC0AaC535CCDB3C01d6787D6413C739ae12bc4;
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    address private constant TEST_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;

    event log_string(string value);
    event log_named_address(string key, address value);
    event log_named_bytes32(string key, bytes32 value);
    event log_named_int(string key, int256 value);
    event log_named_uint(string key, uint256 value);

    function testBaseSepoliaOfficialV3ThirtyMinuteObservation() public {
        if (!VM.envOr("RUN_BASE_SEPOLIA_FORK", false)) {
            emit log_string("Base Sepolia fork verification skipped (explicit opt-in required)");
            return;
        }

        VM.createSelectFork(VM.envString("BASE_SEPOLIA_RPC_URL"));
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "wrong chain");

        _requireContract("factory", FACTORY);
        _requireContract("position manager", POSITION_MANAGER);
        _requireContract("swap router", SWAP_ROUTER);
        _requireContract("WETH", WETH);
        _requireContract("test USDC", TEST_USDC);
        require(IERC20DecimalsMinimal(WETH).decimals() == 18, "wrong WETH decimals");
        require(IERC20DecimalsMinimal(TEST_USDC).decimals() == 6, "wrong USDC decimals");

        address poolAddress = IUniswapV3FactoryMinimal(FACTORY).getPool(WETH, TEST_USDC, FEE);
        require(poolAddress != address(0), "factory returned no pool");
        _requireContract("factory-resolved 0.30% pool", poolAddress);

        IUniswapV3PoolMinimal pool = IUniswapV3PoolMinimal(poolAddress);
        address expectedToken0 = WETH < TEST_USDC ? WETH : TEST_USDC;
        address expectedToken1 = WETH < TEST_USDC ? TEST_USDC : WETH;
        require(pool.token0() == expectedToken0, "wrong token0");
        require(pool.token1() == expectedToken1, "wrong token1");
        require(pool.fee() == FEE, "wrong fee");

        (
            uint160 sqrtPriceX96,
            int24 currentTick,
            uint16 observationIndex,
            uint16 observationCardinality,,,
        ) = pool.slot0();
        uint128 currentLiquidity = pool.liquidity();
        require(sqrtPriceX96 != 0, "uninitialized pool");
        require(currentLiquidity != 0, "zero current liquidity");
        require(observationCardinality > 1, "insufficient observation cardinality");

        (uint32 latestObservationTime,,, bool latestInitialized) =
            pool.observations(observationIndex);
        require(latestInitialized, "latest observation uninitialized");
        require(latestObservationTime != 0, "latest observation zero-dated");

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = WINDOW;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) =
            pool.observe(secondsAgos);
        (int24 arithmeticMeanTick, uint128 harmonicMeanLiquidity) = UniswapV3OracleMath.fromCumulatives(
            tickCumulatives, secondsPerLiquidityCumulativeX128s, WINDOW
        );
        require(harmonicMeanLiquidity != 0, "zero harmonic liquidity");

        uint256 quoteNative =
            UniswapV3OracleMath.quoteAtTick(arithmeticMeanTick, 1e18, WETH, TEST_USDC);
        uint256 priceWad = quoteNative * 1e12;
        require(priceWad != 0, "zero TWAP quote");

        require(block.timestamp <= type(uint32).max, "timestamp exceeds uint32");
        uint32 currentTime = uint32(block.timestamp);
        require(latestObservationTime <= currentTime, "future observation");

        emit log_named_uint("chain ID", block.chainid);
        emit log_named_uint("fork block", block.number);
        emit log_named_uint("fork timestamp", block.timestamp);
        emit log_named_address("factory-resolved pool", poolAddress);
        emit log_named_uint("fee", FEE);
        emit log_named_int("current tick", currentTick);
        emit log_named_int("30-minute arithmetic mean tick", arithmeticMeanTick);
        emit log_named_uint("current liquidity", currentLiquidity);
        emit log_named_uint("30-minute harmonic mean liquidity", harmonicMeanLiquidity);
        emit log_named_uint("observation index", observationIndex);
        emit log_named_uint("observation cardinality", observationCardinality);
        emit log_named_uint("latest observation timestamp", latestObservationTime);
        emit log_named_uint("latest observation age", currentTime - latestObservationTime);
        emit log_named_uint("USDC per WETH TWAP WAD", priceWad);
        emit log_string("Testnet readability is not evidence of production-grade price quality");
    }

    function _requireContract(string memory label, address account) private {
        require(account.code.length != 0, "deployment has no code");
        emit log_named_address(label, account);
        emit log_named_bytes32(string.concat(label, " codehash"), account.codehash);
    }
}
