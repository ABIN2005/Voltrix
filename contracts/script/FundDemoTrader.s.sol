// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AquaVolDemoUSDC } from "../src/tokens/AquaVolDemoUSDC.sol";
import { BaseSepoliaBroadcast } from "./BaseSepoliaBroadcast.sol";

/// @notice Funds the distinct disposable trader with bounded Base Sepolia demo assets.
/// @dev Running without Forge's --broadcast flag performs a simulation only.
contract FundDemoTrader is BaseSepoliaBroadcast {
    address private constant DEMO_USDC = 0xf47584005b5c0F90f292C811016E70e37E3BA9dc;
    uint256 private constant TRADER_GAS = 0.003 ether;
    uint256 private constant TRADER_QUOTE = 5e6;

    error InvalidTrader(address trader);
    error TraderAlreadyFunded(uint256 ethBalance, uint256 quoteBalance);
    error EthTransferFailed();

    event DemoTraderFunded(address indexed trader, uint256 ethAmount, uint256 quoteAmount);

    function run() external {
        (address operator, uint256 privateKey) = _prepareBroadcast();
        address trader = VM.envAddress("TRADER_ADDRESS");
        AquaVolDemoUSDC quote = AquaVolDemoUSDC(DEMO_USDC);

        if (trader == address(0) || trader == operator) revert InvalidTrader(trader);
        uint256 quoteBalance = quote.balanceOf(trader);
        if (trader.balance != 0 || quoteBalance != 0) {
            revert TraderAlreadyFunded(trader.balance, quoteBalance);
        }

        VM.startBroadcast(privateKey);
        quote.mint(trader, TRADER_QUOTE);
        (bool success,) = payable(trader).call{ value: TRADER_GAS }("");
        if (!success) revert EthTransferFailed();
        VM.stopBroadcast();

        require(quote.balanceOf(trader) == TRADER_QUOTE, "wrong quote balance");
        require(trader.balance == TRADER_GAS, "wrong ETH balance");
        emit DemoTraderFunded(trader, TRADER_GAS, TRADER_QUOTE);
    }
}
