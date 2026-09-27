// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice A capped six-decimal test token for the AquaVol Base Sepolia demo.
/// @dev This is not Circle USDC and has no value outside the test deployment.
contract AquaVolDemoUSDC {
    string public constant name = "AquaVol Demo USD";
    string public constant symbol = "avUSD";
    uint8 public constant decimals = 6;
    uint256 public constant MAX_SUPPLY = 10_000_000e6;

    address public immutable minter;
    uint256 public totalSupply;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    error UnauthorizedMinter(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error SupplyCapExceeded(uint256 requestedSupply, uint256 maximumSupply);
    error InsufficientBalance(address account, uint256 available, uint256 required);
    error InsufficientAllowance(
        address owner, address spender, uint256 available, uint256 required
    );

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(address minter_) {
        if (minter_ == address(0)) revert ZeroAddress();
        minter = minter_;
    }

    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert UnauthorizedMinter(msg.sender);
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        uint256 nextSupply = totalSupply + amount;
        if (nextSupply > MAX_SUPPLY) revert SupplyCapExceeded(nextSupply, MAX_SUPPLY);

        totalSupply = nextSupply;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        if (spender == address(0)) revert ZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 available = allowance[from][msg.sender];
        if (available != type(uint256).max) {
            if (available < amount) {
                revert InsufficientAllowance(from, msg.sender, available, amount);
            }
            unchecked {
                allowance[from][msg.sender] = available - amount;
            }
            emit Approval(from, msg.sender, available - amount);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0) || to == address(0)) revert ZeroAddress();
        uint256 available = balanceOf[from];
        if (available < amount) revert InsufficientBalance(from, available, amount);

        unchecked {
            balanceOf[from] = available - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}
