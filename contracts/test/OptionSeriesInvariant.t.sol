// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IOptionSeries } from "../src/interfaces/IOptionSeries.sol";
import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { OptionSeries } from "../src/options/OptionSeries.sol";

interface InvariantVm {
    function warp(uint256 newTimestamp) external;
}

contract InvariantActor {
    function approveToken(MockERC20 token, address spender) external {
        token.approve(spender, type(uint256).max);
    }

    function write(OptionSeries series, uint256 amount) external {
        series.write(amount);
    }

    function exercise(OptionSeries series, uint256 amount) external {
        series.exercise(amount);
    }

    function transferCall(OptionSeries series, address to, uint256 amount) external {
        require(series.transfer(to, amount), "CALL transfer failed");
    }

    function redeem(OptionSeries series) external {
        series.redeem();
    }
}

contract OptionSeriesHandler {
    InvariantVm private constant vm =
        InvariantVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MockERC20 public immutable weth;
    OptionSeries public immutable series;
    InvariantActor public immutable writer;
    InvariantActor public immutable trader;

    constructor(
        MockERC20 weth_,
        MockERC20 usdc_,
        OptionSeries series_,
        InvariantActor writer_,
        InvariantActor trader_
    ) {
        weth = weth_;
        series = series_;
        writer = writer_;
        trader = trader_;
        writer_.approveToken(weth_, address(series_));
        trader_.approveToken(usdc_, address(series_));
    }

    function write(uint96 seed) external {
        if (series.phase() != IOptionSeries.Phase.ACTIVE) return;
        uint256 available = weth.balanceOf(address(writer));
        if (available == 0) return;
        writer.write(series, uint256(seed) % available + 1);
    }

    function transferToTrader(uint96 seed) external {
        uint256 available = series.balanceOf(address(writer));
        if (available == 0) return;
        writer.transferCall(series, address(trader), uint256(seed) % available + 1);
    }

    function enterExerciseWindow() external {
        if (series.phase() == IOptionSeries.Phase.ACTIVE) vm.warp(series.expiry());
    }

    function exercise(uint96 seed) external {
        if (series.phase() != IOptionSeries.Phase.EXERCISE) return;
        uint256 available = series.balanceOf(address(trader));
        if (available == 0) return;
        trader.exercise(series, uint256(seed) % available + 1);
    }

    function closeExerciseWindow() external {
        if (series.phase() != IOptionSeries.Phase.REDEEMABLE) {
            vm.warp(series.expiry() + series.exerciseWindow());
        }
    }

    function redeem() external {
        if (series.phase() == IOptionSeries.Phase.REDEEMABLE && !series.redeemed()) {
            writer.redeem(series);
        }
    }
}

contract OptionSeriesInvariantTest {
    MockERC20 private weth;
    MockERC20 private usdc;
    OptionSeries private series;
    address[] private targetedContracts;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        InvariantActor writer = new InvariantActor();
        InvariantActor trader = new InvariantActor();
        series = new OptionSeries(
            address(writer),
            address(weth),
            address(usdc),
            4_000e18,
            block.timestamp + 7 days,
            24 hours,
            "AquaVol WETH 4000 Call 20261003",
            "avWETH-4000-C-20261003"
        );
        weth.mint(address(writer), 100e18);
        usdc.mint(address(trader), 1_000_000e6);
        OptionSeriesHandler handler = new OptionSeriesHandler(weth, usdc, series, writer, trader);
        targetedContracts.push(address(handler));
    }

    function targetContracts() public view returns (address[] memory) {
        return targetedContracts;
    }

    function invariantLiveSupplyIsFullyBackedBeforeRedemption() public view {
        if (!series.redeemed()) {
            require(
                weth.balanceOf(address(series)) == series.totalWritten() - series.totalExercised(),
                "written/exercised collateral mismatch"
            );
            require(
                weth.balanceOf(address(series)) == series.totalSupply(),
                "live CALL supply is not fully backed"
            );
        }
    }

    function invariantExerciseAccountingCannotExceedWrittenAmount() public view {
        require(series.totalExercised() <= series.totalWritten(), "over-exercised");
    }

    function invariantRedemptionEmptiesSettlementBalances() public view {
        if (series.redeemed()) {
            require(weth.balanceOf(address(series)) == 0, "WETH remains after redemption");
            require(usdc.balanceOf(address(series)) == 0, "USDC remains after redemption");
        }
    }
}
