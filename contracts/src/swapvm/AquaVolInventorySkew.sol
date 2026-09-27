// SPDX-License-Identifier: LicenseRef-Degensoft-SwapVM-1.1
pragma solidity 0.8.30;

/// @custom:license-url https://github.com/1inch/swap-vm/blob/feb16411738331f7d05ae71d4a664154068018fc/LICENSES/SwapVM-1.1.txt
/// @custom:copyright © 2025 Degensoft Ltd
/// @custom:modification AquaVol inventory-skew instruction added 2026-09-26.

import { Context } from "@1inch/swap-vm/contracts/libs/VM.sol";

import { IOptionSeries } from "../interfaces/IOptionSeries.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { InventoryPricing } from "../pricing/InventoryPricing.sol";
import { IAquaVolSpotOracle } from "./AquaVolFairValue.sol";
import { AquaVolInstructionBuilder } from "./AquaVolInstructionBuilder.sol";
import { AquaVolOpcode } from "./AquaVolOpcode.sol";

/// @notice Applies live Aqua inventory risk and spread to an existing fair-value quote.
/// @dev Encoding: [CALL, USDC, spot oracle, Q0, gamma WAD, half-spread WAD].
///      Standard ABI encoding occupies 192 bytes. This instruction only updates the
///      missing quote register; Aqua and SwapVM remain responsible for settlement.
library AquaVolInventorySkew {
    uint256 internal constant ARGUMENTS_LENGTH = 192;
    uint256 internal constant QUOTE_SCALE = 1e30;

    error InvalidArgumentsLength(uint256 actual, uint256 expected);
    error InvalidAddress(address account);
    error UnsupportedPair(address tokenIn, address tokenOut);
    error UnsupportedSwapMode(bool isExactIn);
    error SeriesQuoteMismatch(address expected, address actual);
    error OracleBaseMismatch(address expected, address actual);
    error OracleQuoteMismatch(address expected, address actual);
    error MissingFairValueQuote();
    error FinalQuoteAboveSpotCap(uint256 finalQuote, uint256 spotCap);
    error InsufficientOutputLiquidity(uint256 requested, uint256 available);

    function build(
        address callToken,
        address quoteToken,
        address spotOracle,
        uint256 initialInventory,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) internal pure returns (bytes memory) {
        _validateConfiguration(
            callToken, quoteToken, spotOracle, initialInventory, gammaWad, halfSpreadWad
        );
        return AquaVolInstructionBuilder.build(
            AquaVolOpcode.OPTION_INVENTORY_SKEW,
            abi.encode(callToken, quoteToken, spotOracle, initialInventory, gammaWad, halfSpreadWad)
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
            uint256 initialInventory,
            uint256 gammaWad,
            uint256 halfSpreadWad
        ) = abi.decode(args, (address, address, address, uint256, uint256, uint256));
        _validateConfiguration(
            callToken, quoteToken, spotOracle, initialInventory, gammaWad, halfSpreadWad
        );

        bool isBuy = ctx.query.tokenIn == quoteToken && ctx.query.tokenOut == callToken;
        bool isSellBack = ctx.query.tokenIn == callToken && ctx.query.tokenOut == quoteToken;
        if (!isBuy && !isSellBack) revert UnsupportedPair(ctx.query.tokenIn, ctx.query.tokenOut);
        if ((isBuy && ctx.query.isExactIn) || (isSellBack && !ctx.query.isExactIn)) {
            revert UnsupportedSwapMode(ctx.query.isExactIn);
        }

        uint256 fairValueQuote = isBuy ? ctx.swap.amountIn : ctx.swap.amountOut;
        if (fairValueQuote == 0) revert MissingFairValueQuote();

        IOptionSeries series = IOptionSeries(callToken);
        address underlying = series.underlying();
        address seriesQuote = series.quoteAsset();
        if (seriesQuote != quoteToken) revert SeriesQuoteMismatch(quoteToken, seriesQuote);

        IAquaVolSpotOracle oracle = IAquaVolSpotOracle(spotOracle);
        address oracleBase = oracle.BASE_TOKEN();
        address oracleQuote = oracle.QUOTE_TOKEN();
        if (oracleBase != underlying) revert OracleBaseMismatch(underlying, oracleBase);
        if (oracleQuote != quoteToken) revert OracleQuoteMismatch(quoteToken, oracleQuote);

        uint256 quantity = isBuy ? ctx.swap.amountOut : ctx.swap.amountIn;
        uint256 currentInventory = isBuy ? ctx.swap.balanceOut : ctx.swap.balanceIn;
        InventoryPricing.Result memory result = isBuy
            ? InventoryPricing.buy(
                fairValueQuote,
                initialInventory,
                currentInventory,
                quantity,
                gammaWad,
                halfSpreadWad
            )
            : InventoryPricing.sell(
                fairValueQuote,
                initialInventory,
                currentInventory,
                quantity,
                gammaWad,
                halfSpreadWad
            );

        uint256 spotWad = oracle.read().priceWad;
        uint256 spotCap = isBuy
            ? FullMath.mulDivUp(quantity, spotWad, QUOTE_SCALE)
            : FullMath.mulDiv(quantity, spotWad, QUOTE_SCALE);
        if (result.finalQuote > spotCap) {
            revert FinalQuoteAboveSpotCap(result.finalQuote, spotCap);
        }

        if (isBuy) {
            ctx.swap.amountIn = result.finalQuote;
        } else {
            if (result.finalQuote > ctx.swap.balanceOut) {
                revert InsufficientOutputLiquidity(result.finalQuote, ctx.swap.balanceOut);
            }
            ctx.swap.amountOut = result.finalQuote;
        }
    }

    function _validateConfiguration(
        address callToken,
        address quoteToken,
        address spotOracle,
        uint256 initialInventory,
        uint256 gammaWad,
        uint256 halfSpreadWad
    ) private pure {
        if (callToken == address(0)) revert InvalidAddress(callToken);
        if (quoteToken == address(0)) revert InvalidAddress(quoteToken);
        if (spotOracle == address(0)) revert InvalidAddress(spotOracle);
        if (callToken == quoteToken) revert UnsupportedPair(quoteToken, callToken);
        if (initialInventory == 0 || initialInventory > InventoryPricing.MAX_INITIAL_INVENTORY) {
            revert InventoryPricing.InitialInventoryOutsideDomain(initialInventory);
        }
        if (gammaWad > InventoryPricing.MAX_GAMMA_WAD) {
            revert InventoryPricing.GammaOutsideDomain(gammaWad);
        }
        if (halfSpreadWad > InventoryPricing.MAX_HALF_SPREAD_WAD) {
            revert InventoryPricing.HalfSpreadOutsideDomain(halfSpreadWad);
        }
    }
}
