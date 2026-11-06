// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";

contract LIFETokenTest is Test {
    function test_InitialSupplyExactly10B() public {
        LIFEToken t = new LIFEToken(address(this));
        assertEq(t.totalSupply(), 10_000_000_000e18);
        assertEq(t.balanceOf(address(this)), t.totalSupply());
        assertEq(t.name(), "LIFE AI");
        assertEq(t.symbol(), "LIFE");
        assertEq(t.decimals(), 18);
    }

    function test_ZeroRecipientReverts() public {
        vm.expectRevert();
        new LIFEToken(address(0));
    }

    function test_TransferAllowanceStandard() public {
        LIFEToken t = new LIFEToken(address(this));
        t.approve(address(2), 100);
        vm.prank(address(2));
        t.transferFrom(address(this), address(3), 70);
        assertEq(t.allowance(address(this), address(2)), 30);
        assertEq(t.balanceOf(address(3)), 70);
        t.transfer(address(4), 20);
        assertEq(t.balanceOf(address(4)), 20);
        assertEq(t.totalSupply(), 10_000_000_000e18);
    }

    function test_NoMintBurnAdminUpgradeSelectors() public {
        LIFEToken t = new LIFEToken(address(this));
        bytes[5] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", address(this), 1),
            abi.encodeWithSignature("burn(uint256)", 1),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("owner()"),
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(this), bytes(""))
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(t).call(calls[i]);
            assertFalse(ok);
        }
        assertEq(t.totalSupply(), 10_000_000_000e18);
    }
}
