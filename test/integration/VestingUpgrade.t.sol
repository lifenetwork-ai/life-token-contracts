// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LIFEVestingVaultTest} from "../unit/LIFEVestingVault.t.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEUpgradeTimelock} from "../../src/LIFEUpgradeTimelock.sol";
import {LIFEVestingVaultV2} from "../fixtures/LIFEVestingVaultV2.sol";

contract VestingUpgradeTest is LIFEVestingVaultTest {
    function queue(address target, bytes memory data, bytes32 salt) internal {
        lock.schedule(target, 0, data, bytes32(0), salt, 48 hours);
    }

    function execute(address target, bytes memory data, bytes32 salt) internal {
        lock.execute(target, 0, data, bytes32(0), salt);
    }

    function test_PauseAuthorizationAndAccrual() public {
        vm.expectRevert();
        vault.pause();
        vm.prank(guardian);
        vault.pause();
        assertTrue(vault.paused());
        vm.warp(T + 24 * 30 days);
        assertEq(vault.claimable(ID, LIFEVestingVault.Account.Investor), 240e18);
        vm.expectRevert();
        vault.claim(ID, LIFEVestingVault.Account.Investor);
        vm.expectRevert();
        vault.redirectToFoundation(ID, false, "x");
        vm.expectRevert();
        vault.restoreFutureToInvestor(ID, "x");
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(55));
        vm.prank(investor);
        vm.expectRevert();
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        vm.prank(investor);
        vm.expectRevert();
        vault.cancelWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        vm.expectRevert();
        vault.unpause();
        bytes memory data = abi.encodeCall(vault.unpause, ());
        queue(address(vault), data, "unpause");
        vm.warp(block.timestamp + 48 hours);
        execute(address(vault), data, "unpause");
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 240e18);
    }

    function test_UpgradeDelayAndStatePreservation() public {
        vm.warp(T + 20 * 30 days);
        vault.claim(ID, LIFEVestingVault.Account.Investor);
        vm.warp(T + 24 * 30 days);
        vault.redirectToFoundation(ID, false, "end");
        vm.prank(investor);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(55));
        vm.prank(guardian);
        vault.pause();
        bytes32 beforeState = keccak256(abi.encode(vault.details(ID)));
        LIFEVestingVaultV2 v2 = new LIFEVestingVaultV2();
        bytes memory data = abi.encodeCall(vault.upgradeToAndCall, (address(v2), bytes("")));
        vm.expectRevert();
        vault.upgradeToAndCall(address(v2), "");
        queue(address(vault), data, "v2");
        vm.expectRevert();
        execute(address(vault), data, "v2");
        vm.warp(block.timestamp + 48 hours);
        execute(address(vault), data, "v2");
        assertEq(LIFEVestingVaultV2(address(vault)).version(), 2);
        assertTrue(vault.paused());
        assertEq(keccak256(abi.encode(vault.details(ID))), beforeState);
        vm.expectRevert();
        execute(address(vault), data, "v2");
        bytes memory open = abi.encodeCall(vault.unpause, ());
        queue(address(vault), open, "open");
        vm.warp(block.timestamp + 48 hours);
        execute(address(vault), open, "open");
        vm.prank(address(55));
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 40e18);
        assertEq(token.balanceOf(address(55)), 40e18);
        vm.warp(T + 60 * 30 days);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 240e18);
        assertEq(vault.details(ID).paid, 480e18);
        assertEq(token.totalSupply(), 10_000_000_000e18);
    }

    function test_TimelockedUpgradeRequiresPausedVault() public {
        LIFEVestingVaultV2 next = new LIFEVestingVaultV2();
        bytes memory data = abi.encodeCall(vault.upgradeToAndCall, (address(next), bytes("")));
        queue(address(vault), data, "must-pause");
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert(bytes4(keccak256("ExpectedPause()")));
        execute(address(vault), data, "must-pause");
        vm.prank(guardian);
        vault.pause();
        execute(address(vault), data, "must-pause");
        assertTrue(vault.paused());
        assertEq(LIFEVestingVaultV2(address(vault)).version(), 2);
    }

    function test_TimelockedUpgradeRejectsEOAAndNonUUPS() public {
        vm.prank(guardian);
        vault.pause();
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 original = vm.load(address(vault), slot);
        address[2] memory invalid = [address(0x9876), address(token)];
        for (uint256 i; i < invalid.length; ++i) {
            bytes memory data = abi.encodeCall(vault.upgradeToAndCall, (invalid[i], bytes("")));
            bytes32 salt = bytes32(i + 100);
            queue(address(vault), data, salt);
            vm.warp(block.timestamp + 48 hours);
            // An EOA returns empty data: Solidity rejects decoding before the UUPS catch,
            // and TimelockController wraps the empty revert as FailedCall.
            if (i == 0) vm.expectRevert(bytes4(keccak256("FailedCall()")));
            else vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
            execute(address(vault), data, salt);
            assertEq(vm.load(address(vault), slot), original);
            assertTrue(vault.paused());
        }
    }

    function test_UpgradeKeepsOldAndNewImplementationsForbidden() public {
        vm.prank(guardian);
        vault.pause();
        LIFEVestingVaultV2 next = new LIFEVestingVaultV2();
        bytes memory data = abi.encodeCall(vault.upgradeToAndCall, (address(next), bytes("")));
        queue(address(vault), data, "history");
        vm.warp(block.timestamp + 48 hours);
        execute(address(vault), data, "history");
        assertFalse(vault.isRecipientAllowed(address(impl)));
        assertFalse(vault.isRecipientAllowed(address(next)));
        assertTrue(vault.isRecipientAllowed(address(77)));
        bytes memory open = abi.encodeCall(vault.unpause, ());
        queue(address(vault), open, "history-open");
        vm.warp(block.timestamp + 48 hours);
        execute(address(vault), open, "history-open");
        vm.prank(investor);
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(impl));
        vm.prank(investor);
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(next));
    }

    function test_UpgradeRejectsPendingAndCancelledGrantWallet() public {
        LIFEVestingVaultV2 next = new LIFEVestingVaultV2();
        vm.prank(investor);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(next));
        vm.prank(investor);
        vault.cancelWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        vm.prank(guardian);
        vault.pause();
        bytes memory data = abi.encodeCall(vault.upgradeToAndCall, (address(next), bytes("")));
        queue(address(vault), data, "wallet-collision");
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        execute(address(vault), data, "wallet-collision");
        assertFalse(vault.isRecipientAllowed(address(impl)));
        assertTrue(vault.isRecipientAllowed(address(next)));
    }

    function test_UpgradeRejectsEmissionRecipient() public {
        LIFEVestingVaultV2 next = new LIFEVestingVaultV2();
        vm.prank(address(111));
        emission.proposeRecipient(address(next));
        vm.prank(guardian);
        vault.pause();
        bytes memory data = abi.encodeCall(vault.upgradeToAndCall, (address(next), bytes("")));
        queue(address(vault), data, "emission-collision");
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        execute(address(vault), data, "emission-collision");
    }

    function test_TimelockFloorAndCancel() public {
        assertEq(lock.getMinDelay(), 48 hours);
        assertFalse(lock.hasRole(lock.DEFAULT_ADMIN_ROLE(), address(this)));
        bytes memory low = abi.encodeCall(lock.updateDelay, (1));
        queue(address(lock), low, "low");
        vm.warp(block.timestamp + 48 hours);
        vm.expectRevert();
        execute(address(lock), low, "low");
        bytes memory valid = abi.encodeCall(lock.updateDelay, (72 hours));
        queue(address(lock), valid, "delay");
        vm.warp(block.timestamp + 48 hours);
        execute(address(lock), valid, "delay");
        assertEq(lock.getMinDelay(), 72 hours);
        vm.expectRevert();
        lock.updateDelay(48 hours);
        vm.expectRevert();
        new LIFEUpgradeTimelock(address(0));
    }
}
