// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface IOptionSeries {
    enum Phase {
        ACTIVE,
        EXERCISE,
        REDEEMABLE
    }

    event OptionsWritten(address indexed writer, uint256 collateralAmount, uint256 callAmount);
    event Exercised(
        address indexed holder, uint256 callAmount, uint256 quotePaid, uint256 underlyingSent
    );
    event WriterRedeemed(address indexed writer, uint256 underlyingAmount, uint256 quoteAmount);

    function writer() external view returns (address);
    function underlying() external view returns (address);
    function quoteAsset() external view returns (address);
    function strikePriceWad() external view returns (uint256);
    function expiry() external view returns (uint256);
    function exerciseWindow() external view returns (uint256);
    function totalWritten() external view returns (uint256);
    function totalExercised() external view returns (uint256);
    function totalStrikeCollected() external view returns (uint256);
    function redeemed() external view returns (bool);
    function phase() external view returns (Phase);
    function quotePayment(uint256 callAmount) external view returns (uint256);
    function write(uint256 callAmount) external;
    function exercise(uint256 callAmount) external returns (uint256 quotePaid);
    function redeem() external returns (uint256 underlyingAmount, uint256 quoteAmount);
}
