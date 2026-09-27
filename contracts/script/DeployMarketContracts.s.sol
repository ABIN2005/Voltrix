// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { BaseSepoliaConfig } from "../src/deployment/BaseSepoliaConfig.sol";
import { UniswapV3TwapOracle } from "../src/oracles/uniswap/UniswapV3TwapOracle.sol";
import { OptionSeries } from "../src/options/OptionSeries.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Stage 5 deploys the guarded spot oracle and immutable covered-call series.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract DeployMarketContracts is BaseSepoliaBroadcast {
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    address private constant POOL = 0x0d9516aA182Aa72284802372afaa943E9E77A6D0;
    uint256 private constant STRIKE_PRICE_WAD = 4_000e18;
    uint256 private constant EXPIRY = 1_791_082_800; // 2026-10-04 03:00:00 UTC
    uint256 private constant EXERCISE_WINDOW = 24 hours;
    uint256 private constant MINIMUM_EXPIRY_RUNWAY = 3 days;
    uint128 private constant MINIMUM_HARMONIC_LIQUIDITY = 1;
    uint24 private constant MAXIMUM_TICK_DEVIATION = 500;

    error InsufficientExpiryRunway(uint256 actual, uint256 required);

    event MarketContractsDeployment(
        address indexed oracle,
        address indexed series,
        uint256 strikePriceWad,
        uint256 expiry,
        uint256 exerciseWindow
    );

    function run() external returns (UniswapV3TwapOracle oracle, OptionSeries series) {
        (address operator, uint256 privateKey) = _prepareBroadcast();
        BaseSepoliaConfig.ExternalContracts memory externalContracts =
            BaseSepoliaConfig.officialContracts();
        uint256 runway = EXPIRY > block.timestamp ? EXPIRY - block.timestamp : 0;
        if (runway < MINIMUM_EXPIRY_RUNWAY) {
            revert InsufficientExpiryRunway(runway, MINIMUM_EXPIRY_RUNWAY);
        }

        VM.startBroadcast(privateKey);
        oracle = new UniswapV3TwapOracle(
            externalContracts.factory,
            POOL,
            externalContracts.weth,
            DEMO_USDC,
            BaseSepoliaConfig.POOL_FEE,
            BaseSepoliaConfig.TWAP_WINDOW,
            MINIMUM_HARMONIC_LIQUIDITY,
            BaseSepoliaConfig.MAX_LATEST_OBSERVATION_AGE,
            MAXIMUM_TICK_DEVIATION
        );
        series = new OptionSeries(
            operator,
            externalContracts.weth,
            DEMO_USDC,
            STRIKE_PRICE_WAD,
            EXPIRY,
            EXERCISE_WINDOW,
            "AquaVol WETH 4000 Call",
            "avWETH-4000-C"
        );
        VM.stopBroadcast();

        require(oracle.POOL() == POOL, "wrong pool binding");
        require(oracle.BASE_TOKEN() == externalContracts.weth, "wrong base binding");
        require(oracle.QUOTE_TOKEN() == DEMO_USDC, "wrong quote binding");
        require(series.writer() == operator, "wrong writer binding");
        require(series.expiry() == EXPIRY, "wrong expiry");
        emit MarketContractsDeployment(
            address(oracle), address(series), STRIKE_PRICE_WAD, EXPIRY, EXERCISE_WINDOW
        );
    }
}
