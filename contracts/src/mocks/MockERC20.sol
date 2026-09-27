// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    uint256 public feeBasisPoints;
    address public transferFromCallbackTarget;
    bytes public transferFromCallbackData;
    bool public callbackAttempted;
    bool public callbackSucceeded;

    mapping(address account => uint256 balance) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function setFeeBasisPoints(uint256 feeBasisPoints_) external {
        require(feeBasisPoints_ <= 10_000, "fee too high");
        feeBasisPoints = feeBasisPoints_;
    }

    function setTransferFromCallback(address target, bytes calldata data) external {
        transferFromCallbackTarget = target;
        transferFromCallbackData = data;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
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
        address callbackTarget = transferFromCallbackTarget;
        if (callbackTarget != address(0)) {
            bytes memory callbackData = transferFromCallbackData;
            transferFromCallbackTarget = address(0);
            callbackAttempted = true;
            (callbackSucceeded,) = callbackTarget.call(callbackData);
        }
        uint256 permitted = allowance[from][msg.sender];
        if (permitted != type(uint256).max) {
            require(permitted >= amount, "allowance");
            allowance[from][msg.sender] = permitted - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(to != address(0), "zero address");
        require(balanceOf[from] >= amount, "balance");
        uint256 fee = amount * feeBasisPoints / 10_000;
        uint256 received = amount - fee;
        balanceOf[from] -= amount;
        balanceOf[to] += received;
        totalSupply -= fee;
        emit Transfer(from, to, received);
        if (fee != 0) emit Transfer(from, address(0), fee);
    }
}
