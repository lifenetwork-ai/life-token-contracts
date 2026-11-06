// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEVestingVaultV2} from "../fixtures/LIFEVestingVaultV2.sol";
import {LIFEUpgradeTimelock} from "../../src/LIFEUpgradeTimelock.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract LaunchTest is Test {
    LIFEToken t;
    TGERegistry r;
    LIFEVestingVault impl;
    LIFEUpgradeTimelock lock;
    LIFEEmissionVault e;
    TGEDistributionVault d;
    LIFEVestingVault f;
    address[4] recipients = [address(11), address(12), address(13), address(14)];
    bytes32[4] grants;
    uint64 constant T = 100000;

    function setUp() public virtual {
        vm.warp(T);
        t = new LIFEToken(address(this));
        impl = new LIFEVestingVault();
        lock = new LIFEUpgradeTimelock(address(this));
        f = LIFEVestingVault(address(new ERC1967Proxy(address(impl), abi.encodeCall(LIFEVestingVault.initialize, (LIFEVestingVault.InitParams(t, address(this), address(22), address(lock), address(33)))))));
        r = new TGERegistry(address(this), address(f));
        e = new LIFEEmissionVault(t, r, address(44));
        d = new TGEDistributionVault(t, r, address(this));
        f.configure(r, e, d);
    }

    function test_SystemRecipientsRejectedOnChain() public {
        address[7] memory modules = [address(t), address(lock), address(impl), address(f), address(r), address(e), address(d)];
        t.transfer(address(f), 5_000_000_000e18);
        for (uint256 i; i < modules.length; ++i) {
            vm.expectRevert(TGEDistributionVault.InvalidConfiguration.selector);
            d.setAllocation(modules[i], 1);
            vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
            f.createGrant(0, modules[i], 1);
            vm.prank(address(44));
            vm.expectRevert(LIFEEmissionVault.InvalidConfiguration.selector);
            e.proposeRecipient(modules[i]);
        }
        assertEq(d.totalAllocated(), 0);
        assertEq(f.system().grantCount, 0);
    }

    function test_FoundationCannotBeImplementation() public {
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(LIFEVestingVault.initialize,
            (LIFEVestingVault.InitParams(t, address(this), address(impl), address(lock), address(33)))));
    }

    function test_RecipientPolicyRequiresCompleteConfiguration() public {
        LIFEVestingVault other = LIFEVestingVault(address(new ERC1967Proxy(address(impl), abi.encodeCall(LIFEVestingVault.initialize,
            (LIFEVestingVault.InitParams(t, address(this), address(22), address(lock), address(33)))))));
        TGERegistry rr = new TGERegistry(address(this), address(other));
        TGEDistributionVault dd = new TGEDistributionVault(t, rr, address(this));
        assertFalse(other.isRecipientAllowed(address(55)));
        vm.expectRevert(TGEDistributionVault.InvalidConfiguration.selector);
        dd.setAllocation(address(55), 1);
        LIFEEmissionVault ee = new LIFEEmissionVault(t, rr, address(impl));
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        other.configure(rr, ee, dd);
        ee = new LIFEEmissionVault(t, rr, address(44));
        other.configure(rr, ee, dd);
        dd.setAllocation(address(55), 1);
        assertEq(dd.allocations(address(55)), 1);
    }

    function test_UpgradeRejectsDistributionAllocationCollision() public {
        LIFEVestingVaultV2 next = new LIFEVestingVaultV2();
        d.setAllocation(address(next), 1);
        vm.prank(address(33));
        f.pause();
        bytes memory data = abi.encodeCall(f.upgradeToAndCall, (address(next), bytes("")));
        lock.schedule(address(f), 0, data, bytes32(0), "distribution-collision", 48 hours);
        vm.warp(T + 48 hours);
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        lock.execute(address(f), 0, data, bytes32(0), "distribution-collision");
        assertFalse(f.isRecipientAllowed(address(impl)));
        assertTrue(f.isRecipientAllowed(address(next)));
    }

    function fund() internal {
        t.transfer(address(f), 5_000_000_000e18);
        t.transfer(address(e), 3_100_000_000e18);
        t.transfer(address(d), 1_900_000_000e18);
        uint256[4] memory a = [uint256(2_000_000_000e18), 500_000_000e18, 1_000_000_000e18, 1_500_000_000e18];
        for (uint8 i; i < 4; i++) {
            grants[i] = f.createGrant(i, recipients[i], a[i]);
            assertEq(grants[i], bytes32(uint256(i + 1)));
        }
        f.seal();
        d.setAllocation(address(55), 1_900_000_000e18);
        d.seal();
    }

    function test_LaunchAndAll289Months() public {
        vm.expectRevert();
        r.setTGE(T);
        fund();
        assertTrue(f.isReady());
        r.setTGE(T);
        assertEq(t.balanceOf(address(this)), 0);
        d.claim(address(55));
        assertEq(t.balanceOf(address(55)), 1_900_000_000e18);
        uint256[4] memory amounts = [uint256(2_000_000_000e18), 500_000_000e18, 1_000_000_000e18, 1_500_000_000e18];
        uint256[4] memory cumulative;
        uint256 emission;
        for (uint64 m; m <= 288; m++) {
            vm.warp(T + m * 30 days);
            for (uint256 i; i < 4; i++) {
                LIFEVestingVault v = f;
                v.claim(grants[i], LIFEVestingVault.Account.Investor);
                uint256 cliff = i < 2 ? 12 : 3;
                uint256 n = i < 2 ? 48 : 120;
                if (m > cliff && m <= cliff + n) cumulative[i] = amounts[i] * (m - cliff) / n;
                assertEq(t.balanceOf(recipients[i]), cumulative[i]);
                assertEq(v.details(grants[i]).paid, cumulative[i]);
                assertGe(t.balanceOf(address(f)) + f.system().totalPaid, 5_000_000_000e18);
            }
            if (m >= 48 && m <= 285 && (m - 48) % 3 == 0) emission += 100_000_000e18 / (2 ** ((m - 48) / 48));
            e.release();
            assertEq(t.balanceOf(address(44)), emission);
            assertEq(t.totalSupply(), 10_000_000_000e18);
        }
        assertEq(emission, 3_100_000_000e18);
        assertEq(t.balanceOf(address(f)), 0);
        vm.expectRevert();
        f.createGrant(0, address(77), 1);
    }

    function test_SharedCapsDuplicatesAndFundingAtomicity() public {
        vm.expectRevert();
        f.createGrant(0, address(11), 1);
        t.transfer(address(f), 5_000_000_000e18);
        vm.expectRevert();
        f.createGrant(4, address(11), 1);
        vm.expectRevert();
        f.createGrant(0, address(11), 2_000_000_000e18 + 1);
        vm.prank(address(99));
        vm.expectRevert();
        f.createGrant(0, address(11), 1);
        bytes32 first = f.createGrant(0, address(11), 1);
        assertEq(f.details(first).allocation, 1);
        bytes32 second = f.createGrant(0, address(12), 1);
        assertTrue(first != second);
        assertEq(f.details(second).allocation, 1);
        vm.expectRevert();
        f.seal();
        vm.expectRevert();
        f.configure(r, e, d);
    }

    function test_QuyWalletRotationWithoutRevoke() public {
        fund();
        r.setTGE(T);
        LIFEVestingVault v = f;
        vm.expectRevert();
        v.redirectToFoundation(grants[2], true, "x");
        vm.prank(recipients[2]);
        v.proposeWalletChange(grants[2], LIFEVestingVault.Account.Investor, address(88));
        vm.prank(address(88));
        v.acceptWalletChange(grants[2], LIFEVestingVault.Account.Investor, 1);
        vm.warp(T + 123 * 30 days);
        v.claim(grants[2], LIFEVestingVault.Account.Investor);
        assertEq(t.balanceOf(address(88)), 1_000_000_000e18);
    }
}
