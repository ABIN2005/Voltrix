// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol fair-value instruction added 2026-09-26.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { IOptionSeries } from "../interfaces/IOptionSeries.sol";
import { IVolatilityRegistry } from "../oracles/interfaces/IVolatilityRegistry.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { BlackScholes } from "../pricing/BlackScholes.sol";
import { AquaVolInstructionBuilder } from "./AquaVolInstructionBuilder.sol";
import { AquaVolOpcode } from "./AquaVolOpcode.sol";

interface IAquaVolSpotOracle {
    struct Observation {
        uint256 priceWad;
        int24 arithmeticMeanTick;
        uint128 harmonicMeanLiquidity;
        uint32 windowStart;
        uint32 windowEnd;
        uint32 latestObservationTime;
    }

    function BASE_TOKEN() external view returns (address);
    function QUOTE_TOKEN() external view returns (address);
    function read() external view returns (Observation memory result);
}

/// @notice Computes unskewed European-call fair value from strategy-bound sources.
/// @dev Encoding: [CALL, USDC, spot oracle, volatility registry, maximum volatility age].
///      The standard ABI encoding occupies 160 bytes. This instruction only updates the
///      missing swap amount register; Aqua and SwapVM remain responsible for settlement.
library AquaVolFairValue {
    uint256 internal constant ARGUMENTS_LENGTH = 160;
    uint256 internal constant QUOTE_SCALE = 1e30;
    uint256 internal constant MAXIMUM_VOLATILITY_AGE = 7 days;
    uint256 internal constant MAXIMUM_FUTURE_DRIFT = 15 seconds;
    uint256 internal constant MIN_VOLATILITY_WAD = 0.0001e18;
    uint256 internal constant MAX_VOLATILITY_WAD = 5e18;

    error InvalidArgumentsLength(uint256 actual, uint256 expected);
    error InvalidAddress(address account);
    error InvalidMaximumVolatilityAge(uint256 maximumAge);
    error UnsupportedPair(address tokenIn, address tokenOut);
    error UnsupportedSwapMode(bool isExactIn);
    error SeriesQuoteMismatch(address expected, address actual);
    error OracleBaseMismatch(address expected, address actual);
    error OracleQuoteMismatch(address expected, address actual);
    error SeriesExpired(uint256 expiry, uint256 currentTime);
    error ZeroCallAmount();
    error InsufficientOutputLiquidity(uint256 requested, uint256 available);
    error VolatilityMissing();
    error VolatilityOutOfRange(uint256 volatilityWad);
    error VolatilityTimestampMissing();
    error VolatilityTimestampTooFarInFuture(uint256 updatedAt, uint256 currentTime);
    error VolatilityStale(uint256 age, uint256 maximumAge);
    error ZeroPremium();
    error ZeroQuoteAmount();
    error FairValueRegisterAlreadySet(uint256 currentAmount);

    function build(
        address callToken,
        address quoteToken,
        address spotOracle,
        address volatilityRegistry,
        uint256 maximumVolatilityAge
    ) internal pure returns (bytes memory) {
        _validateConfiguration(
            callToken, quoteToken, spotOracle, volatilityRegistry, maximumVolatilityAge
        );
        return AquaVolInstructionBuilder.build(
            AquaVolOpcode.OPTION_FAIR_VALUE,
            abi.encode(callToken, quoteToken, spotOracle, volatilityRegistry, maximumVolatilityAge)
        );
    }

    function exec(Context memory ctx, bytes calldata args) internal view {
        if (args.length != ARGUMENTS_LENGTH) {
            revert InvalidArgumentsLength(args.length, ARGUMENTS_LENGTH);
        }

        (
            address callToken,
            address quoteToken,
            address spotOracle,
            address volatilityRegistry,
            uint256 maximumVolatilityAge
        ) = abi.decode(args, (address, address, address, address, uint256));
        _validateConfiguration(
            callToken, quoteToken, spotOracle, volatilityRegistry, maximumVolatilityAge
        );

        bool isBuy = ctx.query.tokenIn == quoteToken && ctx.query.tokenOut == callToken;
        bool isSellBack = ctx.query.tokenIn == callToken && ctx.query.tokenOut == quoteToken;
        if (!isBuy && !isSellBack) revert UnsupportedPair(ctx.query.tokenIn, ctx.query.tokenOut);
        if ((isBuy && ctx.query.isExactIn) || (isSellBack && !ctx.query.isExactIn)) {
            revert UnsupportedSwapMode(ctx.query.isExactIn);
        }

        uint256 currentMissingAmount = isBuy ? ctx.swap.amountIn : ctx.swap.amountOut;
        if (currentMissingAmount != 0) {
            revert FairValueRegisterAlreadySet(currentMissingAmount);
        }

        uint256 callAmount = isBuy ? ctx.swap.amountOut : ctx.swap.amountIn;
        if (callAmount == 0) revert ZeroCallAmount();
        if (isBuy && callAmount > ctx.swap.balanceOut) {
            revert InsufficientOutputLiquidity(callAmount, ctx.swap.balanceOut);
        }

        IOptionSeries series = IOptionSeries(callToken);
        address underlying = series.underlying();
        address seriesQuote = series.quoteAsset();
        if (seriesQuote != quoteToken) revert SeriesQuoteMismatch(quoteToken, seriesQuote);

        IAquaVolSpotOracle oracle = IAquaVolSpotOracle(spotOracle);
        address oracleBase = oracle.BASE_TOKEN();
        address oracleQuote = oracle.QUOTE_TOKEN();
        if (oracleBase != underlying) revert OracleBaseMismatch(underlying, oracleBase);
        if (oracleQuote != quoteToken) revert OracleQuoteMismatch(quoteToken, oracleQuote);

        uint256 expiry = series.expiry();
        if (block.timestamp >= expiry) revert SeriesExpired(expiry, block.timestamp);

        (uint256 volatilityWad, uint64 updatedAt) =
            IVolatilityRegistry(volatilityRegistry).read(callToken);
        if (volatilityWad == 0) revert VolatilityMissing();
        if (volatilityWad < MIN_VOLATILITY_WAD || volatilityWad > MAX_VOLATILITY_WAD) {
            revert VolatilityOutOfRange(volatilityWad);
        }
        if (updatedAt == 0) revert VolatilityTimestampMissing();
        if (
            updatedAt > block.timestamp
                && uint256(updatedAt) - block.timestamp > MAXIMUM_FUTURE_DRIFT
        ) {
            revert VolatilityTimestampTooFarInFuture(updatedAt, block.timestamp);
        }
        uint256 volatilityAge = updatedAt > block.timestamp ? 0 : block.timestamp - updatedAt;
        if (volatilityAge > maximumVolatilityAge) {
            revert VolatilityStale(volatilityAge, maximumVolatilityAge);
        }

        uint256 spotWad = oracle.read().priceWad;
        uint256 premiumWad = BlackScholes.callPrice(
            spotWad, series.strikePriceWad(), expiry - block.timestamp, volatilityWad
        );
        if (premiumWad == 0) revert ZeroPremium();

        if (isBuy) {
            ctx.swap.amountIn = FullMath.mulDivUp(callAmount, premiumWad, QUOTE_SCALE);
        } else {
            uint256 quoteAmount = FullMath.mulDiv(callAmount, premiumWad, QUOTE_SCALE);
            if (quoteAmount == 0) revert ZeroQuoteAmount();
            if (quoteAmount > ctx.swap.balanceOut) {
                revert InsufficientOutputLiquidity(quoteAmount, ctx.swap.balanceOut);
            }
            ctx.swap.amountOut = quoteAmount;
        }
    }

    function _validateConfiguration(
        address callToken,
        address quoteToken,
        address spotOracle,
        address volatilityRegistry,
        uint256 maximumVolatilityAge
    ) private pure {
        if (callToken == address(0)) revert InvalidAddress(callToken);
        if (quoteToken == address(0)) revert InvalidAddress(quoteToken);
        if (spotOracle == address(0)) revert InvalidAddress(spotOracle);
        if (volatilityRegistry == address(0)) revert InvalidAddress(volatilityRegistry);
        if (callToken == quoteToken) revert UnsupportedPair(quoteToken, callToken);
        if (maximumVolatilityAge == 0 || maximumVolatilityAge > MAXIMUM_VOLATILITY_AGE) {
            revert InvalidMaximumVolatilityAge(maximumVolatilityAge);
        }
    }
}
