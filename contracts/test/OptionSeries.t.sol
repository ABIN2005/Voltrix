// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { MockERC20 } from "../src/mocks/MockERC20.sol";
import { OptionSeries } from "../src/options/OptionSeries.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
}

contract SeriesActor {
    function approveToken(MockERC20 token, address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function write(OptionSeries series, uint256 amount) external {
        series.write(amount);
    }

    function exercise(OptionSeries series, uint256 amount) external {
        series.exercise(amount);
    }

    function redeem(OptionSeries series) external {
        series.redeem();
    }

    function transferCall(OptionSeries series, address to, uint256 amount) external {
        require(series.transfer(to, amount), "CALL transfer failed");
    }
}

contract OptionSeriesTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 private constant STRIKE = 4_000e18;
    uint256 private constant WINDOW = 24 hours;

    MockERC20 private weth;
    MockERC20 private usdc;
    SeriesActor private writer;
    SeriesActor private trader;
    OptionSeries private series;
    uint256 private expiry;

    function setUp() public {
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        writer = new SeriesActor();
        trader = new SeriesActor();
        expiry = block.timestamp + 7 days;
        series = new OptionSeries(
            address(writer),
            address(weth),
            address(usdc),
            STRIKE,
            expiry,
            WINDOW,
            "AquaVol WETH 4000 Call 20261003",
            "avWETH-4000-C-20261003"
        );
        weth.mint(address(writer), 20e18);
        usdc.mint(address(trader), 100_000e6);
        writer.approveToken(weth, address(series), type(uint256).max);
        trader.approveToken(usdc, address(series), type(uint256).max);
    }

    function testWriteLocksCollateralAndMintsOneToOne() public {
        writer.write(series, 10e18);
        _assertEq(weth.balanceOf(address(series)), 10e18, "locked WETH");
        _assertEq(series.balanceOf(address(writer)), 10e18, "writer CALL");
        _assertEq(series.totalSupply(), 10e18, "CALL supply");
        _assertEq(series.totalWritten(), 10e18, "written accounting");
    }

    function testOnlyWriterCanWrite() public {
        (bool success,) = address(trader).call(abi.encodeCall(SeriesActor.write, (series, 1e18)));
        _assertFalse(success, "non-writer write succeeded");
    }

    function testWriteRejectsIncompleteCollateralTransfer() public {
        weth.setFeeBasisPoints(100);
        (bool success,) = address(writer).call(abi.encodeCall(SeriesActor.write, (series, 1e18)));
        _assertFalse(success, "fee-on-transfer write succeeded");
        _assertEq(weth.balanceOf(address(series)), 0, "reverted collateral");
        _assertEq(series.totalSupply(), 0, "reverted mint");
    }

    function testWriteRejectsAtExpiry() public {
        vm.warp(expiry);
        (bool success,) = address(writer).call(abi.encodeCall(SeriesActor.write, (series, 1e18)));
        _assertFalse(success, "write at expiry succeeded");
    }

    function testExerciseAtExpiryIsAtomic() public {
        writer.write(series, 2e18);
        writer.transferCall(series, address(trader), 1e18);
        vm.warp(expiry);
        trader.exercise(series, 1e18);
        _assertEq(usdc.balanceOf(address(series)), 4_000e6, "strike collected");
        _assertEq(weth.balanceOf(address(trader)), 1e18, "WETH delivered");
        _assertEq(series.balanceOf(address(trader)), 0, "CALL burned");
        _assertEq(series.totalExercised(), 1e18, "exercise accounting");
        _assertEq(weth.balanceOf(address(series)), series.totalSupply(), "live backing");
    }

    function testExerciseRoundsFractionalPaymentUp() public {
        writer.write(series, 1);
        writer.transferCall(series, address(trader), 1);
        vm.warp(expiry);
        _assertEq(series.quotePayment(1), 1, "one CALL wei costs one USDC unit");
        trader.exercise(series, 1);
        _assertEq(series.totalStrikeCollected(), 1, "rounded strike accounting");
        _assertEq(weth.balanceOf(address(trader)), 1, "fractional WETH delivery");
    }

    function testExerciseRejectsIncompleteQuoteTransferAtomically() public {
        writer.write(series, 1e18);
        writer.transferCall(series, address(trader), 1e18);
        usdc.setFeeBasisPoints(100);
        vm.warp(expiry);

        (bool success,) = address(trader).call(abi.encodeCall(SeriesActor.exercise, (series, 1e18)));

        _assertFalse(success, "fee-on-transfer exercise succeeded");
        _assertEq(series.balanceOf(address(trader)), 1e18, "CALL burn was not reverted");
        _assertEq(weth.balanceOf(address(trader)), 0, "WETH escaped");
        _assertEq(series.totalExercised(), 0, "exercise accounting changed");
    }

    function testExerciseBlocksReentrantTokenCallback() public {
        writer.write(series, 1e18);
        writer.transferCall(series, address(trader), 1e18);
        usdc.setTransferFromCallback(
            address(series), abi.encodeCall(OptionSeries.exercise, (uint256(1)))
        );
        vm.warp(expiry);

        trader.exercise(series, 1e18);

        require(usdc.callbackAttempted(), "callback not attempted");
        _assertFalse(usdc.callbackSucceeded(), "reentrant exercise succeeded");
        _assertEq(series.totalExercised(), 1e18, "outer exercise failed");
        _assertEq(weth.balanceOf(address(series)), series.totalSupply(), "backing changed");
    }

    function testExerciseRejectsBeforeAndAfterWindow() public {
        writer.write(series, 2e18);
        writer.transferCall(series, address(trader), 2e18);
        (bool beforeSuccess,) =
            address(trader).call(abi.encodeCall(SeriesActor.exercise, (series, 1e18)));
        _assertFalse(beforeSuccess, "early exercise succeeded");
        vm.warp(expiry + WINDOW);
        (bool afterSuccess,) =
            address(trader).call(abi.encodeCall(SeriesActor.exercise, (series, 1e18)));
        _assertFalse(afterSuccess, "late exercise succeeded");
    }

    function testBurnedCallCannotBeExercisedTwice() public {
        writer.write(series, 1e18);
        writer.transferCall(series, address(trader), 1e18);
        vm.warp(expiry);
        trader.exercise(series, 1e18);
        (bool success,) = address(trader).call(abi.encodeCall(SeriesActor.exercise, (series, 1e18)));
        _assertFalse(success, "double exercise succeeded");
        _assertEq(series.totalExercised(), 1e18, "exercise accounting changed");
    }

    function testWriterRedeemsRemainingCollateralAndStrikeOnce() public {
        writer.write(series, 2e18);
        writer.transferCall(series, address(trader), 1e18);
        vm.warp(expiry);
        trader.exercise(series, 1e18);
        vm.warp(expiry + WINDOW);
        writer.redeem(series);
        _assertEq(weth.balanceOf(address(writer)), 19e18, "remaining WETH returned");
        _assertEq(usdc.balanceOf(address(writer)), 4_000e6, "strike proceeds returned");
        _assertEq(weth.balanceOf(address(series)), 0, "series WETH emptied");
        _assertEq(usdc.balanceOf(address(series)), 0, "series USDC emptied");
        (bool success,) = address(writer).call(abi.encodeCall(SeriesActor.redeem, (series)));
        _assertFalse(success, "second redemption succeeded");
    }

    function testRedemptionRequiresWriterAndClosedExerciseWindow() public {
        writer.write(series, 1e18);
        (bool earlySuccess,) = address(writer).call(abi.encodeCall(SeriesActor.redeem, (series)));
        _assertFalse(earlySuccess, "early redemption succeeded");

        vm.warp(expiry + WINDOW);
        (bool traderSuccess,) = address(trader).call(abi.encodeCall(SeriesActor.redeem, (series)));
        _assertFalse(traderSuccess, "non-writer redemption succeeded");
        _assertEq(weth.balanceOf(address(series)), 1e18, "collateral escaped");
    }

    function testCallRemainsTransferableAfterExpiry() public {
        writer.write(series, 1e18);
        vm.warp(expiry + WINDOW);
        writer.transferCall(series, address(trader), 1e18);
        _assertEq(series.balanceOf(address(trader)), 1e18, "expired CALL transfer");
    }

    function testFuzzFractionalExercisePreservesBacking(uint96 rawAmount) public {
        uint256 amount = uint256(rawAmount) % 10e18 + 1;
        writer.write(series, amount);
        writer.transferCall(series, address(trader), amount);
        vm.warp(expiry);
        trader.exercise(series, amount);
        _assertEq(weth.balanceOf(address(series)), series.totalSupply(), "fuzz live backing");
        _assertEq(series.totalExercised(), amount, "fuzz exercise amount");
        require(series.totalStrikeCollected() >= amount * STRIKE / 1e30, "rounding down");
    }

    function _assertEq(uint256 actual, uint256 expected, string memory reason) private pure {
        require(actual == expected, reason);
    }

    function _assertFalse(bool value, string memory reason) private pure {
        require(!value, reason);
    }
}
