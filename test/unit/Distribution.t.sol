// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";
import {ReadinessMock} from "./Schedule.t.sol";

contract DistributionTest is Test {
    LIFEToken t;
    TGERegistry r;
    LIFEEmissionVault e;
    TGEDistributionVault d;
    uint64 constant T = 100000;

    function setUp() public {
        vm.warp(T);
        t = new LIFEToken(address(this));
        ReadinessMock ready = new ReadinessMock();
        ready.setReady(true);
        r = new TGERegistry(address(this), address(ready));
        e = new LIFEEmissionVault(t, r, address(11));
        d = new TGEDistributionVault(t, r, address(this));
    }

    function test_EmissionReleaseAllStages() public {
        assertFalse(e.isReady());
        t.transfer(address(e), 3_100_000_000e18);
        assertTrue(e.isReady());
        assertEq(e.release(), 0);
        r.setTGE(T);
        assertEq(e.release(), 0);
        vm.warp(T + 48 * 30 days);
        assertEq(e.releasable(), 100_000_000e18);
        assertEq(e.release(), 100_000_000e18);
        assertEq(e.release(), 0);
        vm.warp(T + 96 * 30 days);
        assertEq(e.release(), 1_550_000_000e18);
        vm.warp(T + 285 * 30 days);
        assertEq(e.release(), 1_450_000_000e18);
        assertEq(t.balanceOf(address(11)), 3_100_000_000e18);
        t.transfer(address(e), 10);
        assertEq(e.release(), 0);
    }

    function test_EmissionRecipientRotation() public {
        vm.expectRevert();
        e.proposeRecipient(address(22));
        vm.prank(address(11));
        vm.expectRevert();
        e.proposeRecipient(address(0));
        vm.prank(address(11));
        vm.expectRevert();
        e.proposeRecipient(address(e));
        vm.prank(address(11));
        e.proposeRecipient(address(22));
        vm.expectRevert();
        e.acceptRecipient();
        vm.prank(address(22));
        e.acceptRecipient();
        t.transfer(address(e), 3_100_000_000e18);
        r.setTGE(T);
        vm.warp(T + 48 * 30 days);
        e.release();
        assertEq(t.balanceOf(address(22)), 100_000_000e18);
    }

    function test_DistributionSealAndClaim() public {
        assertFalse(d.isReady());
        d.setAllocation(address(11), 1e18);
        d.setAllocation(address(11), 1_000_000_000e18);
        vm.expectRevert();
        d.seal();
        d.setAllocation(address(22), 900_000_000e18);
        vm.expectRevert();
        d.seal();
        t.transfer(address(d), 1_900_000_000e18);
        d.seal();
        assertTrue(d.isReady());
        assertEq(d.claim(address(11)), 0);
        vm.expectRevert();
        d.seal();
        vm.expectRevert();
        d.setAllocation(address(33), 1);
        r.setTGE(T + 10);
        assertEq(d.claim(address(11)), 0);
        vm.warp(T + 10);
        vm.prank(address(99));
        assertEq(d.claim(address(11)), 1_000_000_000e18);
        assertEq(t.balanceOf(address(99)), 0);
        assertEq(d.claim(address(11)), 0);
        assertEq(d.claim(address(22)), 900_000_000e18);
        assertEq(d.claim(address(33)), 0);
        assertEq(t.balanceOf(address(d)), 0);
    }

    function test_DistributionRejectsTokenRecipientWithoutChangingAllocation() public {
        d.setAllocation(address(11), 1e18);
        vm.expectRevert(TGEDistributionVault.InvalidConfiguration.selector);
        d.setAllocation(address(t), 1_900_000_000e18 - 1e18);
        assertEq(d.totalAllocated(), 1e18);
        assertEq(d.allocations(address(t)), 0);
        assertEq(d.allocations(address(11)), 1e18);
    }

    function test_DistributionInvalidInputs() public {
        vm.prank(address(99));
        vm.expectRevert();
        d.setAllocation(address(11), 1);
        vm.expectRevert();
        d.setAllocation(address(0), 1);
        vm.expectRevert();
        d.setAllocation(address(d), 1);
        vm.expectRevert();
        d.setAllocation(address(11), 1_900_000_000e18 + 1);
        vm.expectRevert();
        d.claim(address(11));
        r.setTGE(T);
        vm.expectRevert();
        d.setAllocation(address(11), 1);
    }

    function test_DistributionRejectsRegistryRecipient() public {
        vm.expectRevert(TGEDistributionVault.InvalidConfiguration.selector);
        d.setAllocation(address(r), 1);
    }

    function test_EmissionRejectsTokenAndRegistryRecipients() public {
        vm.expectRevert(LIFEEmissionVault.InvalidConfiguration.selector);
        new LIFEEmissionVault(t, r, address(t));
        vm.expectRevert(LIFEEmissionVault.InvalidConfiguration.selector);
        new LIFEEmissionVault(t, r, address(r));
    }

    function test_InvalidConstructors() public {
        vm.expectRevert();
        new LIFEEmissionVault(t, r, address(0));
        vm.expectRevert();
        new TGEDistributionVault(t, r, address(0));
    }
}
