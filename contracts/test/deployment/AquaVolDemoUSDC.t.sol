// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { AquaVolDemoUSDC } from "../../src/tokens/AquaVolDemoUSDC.sol";

contract DemoTokenActor {
    function mint(AquaVolDemoUSDC token, address to, uint256 amount) external {
        token.mint(to, amount);
    }

    function pull(AquaVolDemoUSDC token, address from, address to, uint256 amount) external {
        require(token.transferFrom(from, to, amount), "pull failed");
    }
}

contract AquaVolDemoUSDCTest {
    function testMetadataAndImmutableMinterAreExplicitlyDemoOnly() public {
        AquaVolDemoUSDC token = new AquaVolDemoUSDC(address(this));

        require(
            keccak256(bytes(token.name())) == keccak256(bytes("AquaVol Demo USD")), "wrong name"
        );
        require(keccak256(bytes(token.symbol())) == keccak256(bytes("avUSD")), "wrong symbol");
        require(token.decimals() == 6, "wrong decimals");
        require(token.minter() == address(this), "wrong minter");
        require(token.MAX_SUPPLY() == 10_000_000e6, "wrong cap");
    }

    function testConstructorRejectsZeroMinter() public {
        try new AquaVolDemoUSDC(address(0)) returns (AquaVolDemoUSDC) {
            revert("zero minter accepted");
        } catch (bytes memory reason) {
            _assertSelector(reason, AquaVolDemoUSDC.ZeroAddress.selector);
        }
    }

    function testOnlyMinterCanMint() public {
        AquaVolDemoUSDC token = new AquaVolDemoUSDC(address(this));
        DemoTokenActor actor = new DemoTokenActor();

        (bool ok, bytes memory reason) =
            address(actor).call(abi.encodeCall(DemoTokenActor.mint, (token, address(actor), 1e6)));
        require(!ok, "unauthorized mint succeeded");
        _assertSelector(reason, AquaVolDemoUSDC.UnauthorizedMinter.selector);
        require(token.totalSupply() == 0, "supply changed");
    }

    function testMintRejectsZeroRecipientAndAmount() public {
        AquaVolDemoUSDC token = new AquaVolDemoUSDC(address(this));

        (bool recipientOk, bytes memory recipientReason) =
            address(token).call(abi.encodeCall(AquaVolDemoUSDC.mint, (address(0), 1e6)));
        require(!recipientOk, "zero recipient accepted");
        _assertSelector(recipientReason, AquaVolDemoUSDC.ZeroAddress.selector);

        (bool amountOk, bytes memory amountReason) =
            address(token).call(abi.encodeCall(AquaVolDemoUSDC.mint, (address(this), 0)));
        require(!amountOk, "zero mint accepted");
        _assertSelector(amountReason, AquaVolDemoUSDC.ZeroAmount.selector);
    }

    function testSupplyCapIsEnforced() public {
        AquaVolDemoUSDC token = new AquaVolDemoUSDC(address(this));
        token.mint(address(this), token.MAX_SUPPLY());

        (bool ok, bytes memory reason) =
            address(token).call(abi.encodeCall(AquaVolDemoUSDC.mint, (address(this), 1)));
        require(!ok, "cap exceeded");
        _assertSelector(reason, AquaVolDemoUSDC.SupplyCapExceeded.selector);
        require(token.totalSupply() == token.MAX_SUPPLY(), "cap accounting changed");
    }

    function testTransferAndAllowanceAccounting() public {
        AquaVolDemoUSDC token = new AquaVolDemoUSDC(address(this));
        DemoTokenActor spender = new DemoTokenActor();
        address recipient = address(0xB0B);

        token.mint(address(this), 100e6);
        require(token.transfer(recipient, 20e6), "transfer failed");
        require(token.balanceOf(recipient) == 20e6, "recipient transfer balance");

        require(token.approve(address(spender), 30e6), "approval failed");
        spender.pull(token, address(this), recipient, 12e6);

        require(token.balanceOf(address(this)) == 68e6, "owner balance");
        require(token.balanceOf(recipient) == 32e6, "recipient pull balance");
        require(token.allowance(address(this), address(spender)) == 18e6, "remaining allowance");
        require(token.totalSupply() == 100e6, "supply changed on transfer");
    }

    function _assertSelector(bytes memory reason, bytes4 expected) private pure {
        require(reason.length >= 4, "missing revert selector");
        bytes4 actual;
        assembly ("memory-safe") {
            actual := mload(add(reason, 0x20))
        }
        require(actual == expected, "wrong revert selector");
    }
}
