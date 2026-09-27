// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { IOptionSeries } from "../interfaces/IOptionSeries.sol";
import { FullMath } from "../libraries/FullMath.sol";

interface IERC20Asset {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @notice A single-writer, fully collateralized European WETH call series.
contract OptionSeries is IOptionSeries {
    uint8 public constant decimals = 18;
    uint256 private constant WAD_TO_USDC_DENOMINATOR = 1e30;

    string public name;
    string public symbol;
    uint256 public totalSupply;
    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    address public immutable writer;
    address public immutable underlying;
    address public immutable quoteAsset;
    uint256 public immutable strikePriceWad;
    uint256 public immutable expiry;
    uint256 public immutable exerciseWindow;

    uint256 public totalWritten;
    uint256 public totalExercised;
    uint256 public totalStrikeCollected;
    bool public redeemed;
    uint256 private _locked = 1;

    error ZeroAddress();
    error InvalidAssetPair();
    error InvalidTokenDecimals(address token, uint8 expected, uint8 actual);
    error InvalidSeriesTerms();
    error Unauthorized();
    error WrongPhase(Phase expected, Phase actual);
    error ZeroAmount();
    error InsufficientBalance();
    error InsufficientAllowance();
    error UnsafeTokenTransfer(address token);
    error IncompleteTokenTransfer(address token, uint256 expected, uint256 received);
    error AlreadyRedeemed();
    error Reentrancy();

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(
        address writer_,
        address underlying_,
        address quoteAsset_,
        uint256 strikePriceWad_,
        uint256 expiry_,
        uint256 exerciseWindow_,
        string memory name_,
        string memory symbol_
    ) {
        if (writer_ == address(0) || underlying_ == address(0) || quoteAsset_ == address(0)) {
            revert ZeroAddress();
        }
        if (underlying_ == quoteAsset_) revert InvalidAssetPair();
        if (
            strikePriceWad_ == 0 || expiry_ <= block.timestamp || exerciseWindow_ == 0
                || expiry_ > type(uint256).max - exerciseWindow_ || bytes(name_).length == 0
                || bytes(symbol_).length == 0
        ) revert InvalidSeriesTerms();

        _requireDecimals(underlying_, 18);
        _requireDecimals(quoteAsset_, 6);
        writer = writer_;
        underlying = underlying_;
        quoteAsset = quoteAsset_;
        strikePriceWad = strikePriceWad_;
        expiry = expiry_;
        exerciseWindow = exerciseWindow_;
        name = name_;
        symbol = symbol_;
    }

    function phase() public view returns (Phase) {
        if (block.timestamp < expiry) return Phase.ACTIVE;
        if (block.timestamp < expiry + exerciseWindow) return Phase.EXERCISE;
        return Phase.REDEEMABLE;
    }

    /// @notice USDC units required for `callAmount`, rounded in the writer's favor.
    function quotePayment(uint256 callAmount) public view returns (uint256) {
        return FullMath.mulDivUp(callAmount, strikePriceWad, WAD_TO_USDC_DENOMINATOR);
    }

    function write(uint256 callAmount) external nonReentrant {
        if (msg.sender != writer) revert Unauthorized();
        Phase current = phase();
        if (current != Phase.ACTIVE) revert WrongPhase(Phase.ACTIVE, current);
        if (callAmount == 0) revert ZeroAmount();

        uint256 nextWritten = totalWritten + callAmount;
        _takeExact(underlying, msg.sender, callAmount);
        totalWritten = nextWritten;
        _mint(msg.sender, callAmount);
        emit OptionsWritten(msg.sender, callAmount, callAmount);
    }

    function exercise(uint256 callAmount) external nonReentrant returns (uint256 quotePaid) {
        Phase current = phase();
        if (current != Phase.EXERCISE) revert WrongPhase(Phase.EXERCISE, current);
        if (callAmount == 0) revert ZeroAmount();
        quotePaid = quotePayment(callAmount);

        _takeExact(quoteAsset, msg.sender, quotePaid);
        _burn(msg.sender, callAmount);
        totalExercised += callAmount;
        totalStrikeCollected += quotePaid;
        _safeTransfer(underlying, msg.sender, callAmount);
        emit Exercised(msg.sender, callAmount, quotePaid, callAmount);
    }

    function redeem()
        external
        nonReentrant
        returns (uint256 underlyingAmount, uint256 quoteAmount)
    {
        if (msg.sender != writer) {
            revert Unauthorized();
        }
        Phase current = phase();
        if (current != Phase.REDEEMABLE) revert WrongPhase(Phase.REDEEMABLE, current);
        if (redeemed) revert AlreadyRedeemed();

        redeemed = true;
        underlyingAmount = IERC20Asset(underlying).balanceOf(address(this));
        quoteAmount = IERC20Asset(quoteAsset).balanceOf(address(this));
        if (underlyingAmount != 0) _safeTransfer(underlying, msg.sender, underlyingAmount);
        if (quoteAmount != 0) _safeTransfer(quoteAsset, msg.sender, quoteAmount);
        emit WriterRedeemed(msg.sender, underlyingAmount, quoteAmount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 permitted = allowance[from][msg.sender];
        if (permitted != type(uint256).max) {
            if (permitted < amount) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = permitted - amount;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) private {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) private {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) revert InsufficientBalance();
        unchecked {
            balanceOf[from] = fromBalance - amount;
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    function _takeExact(address token, address from, uint256 amount) private {
        uint256 beforeBalance = IERC20Asset(token).balanceOf(address(this));
        _safeTransferFrom(token, from, address(this), amount);
        uint256 afterBalance = IERC20Asset(token).balanceOf(address(this));
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (received != amount) revert IncompleteTokenTransfer(token, amount, received);
    }

    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        if (!success || (data.length != 0 && (data.length != 32 || !abi.decode(data, (bool))))) {
            revert UnsafeTokenTransfer(token);
        }
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, amount)
        );
        if (!success || (data.length != 0 && (data.length != 32 || !abi.decode(data, (bool))))) {
            revert UnsafeTokenTransfer(token);
        }
    }

    function _requireDecimals(address token, uint8 expected) private view {
        uint8 actual = IERC20Asset(token).decimals();
        if (actual != expected) revert InvalidTokenDecimals(token, expected, actual);
    }
}
