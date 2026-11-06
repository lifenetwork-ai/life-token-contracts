// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEUpgradeTimelock} from "../../src/LIFEUpgradeTimelock.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";
import {LegacyLIFEVestingVault} from "../fixtures/LegacyLIFEVestingVault.sol";

contract LateGrantsTest is Test {
    uint256 constant BUDGET = 5_000_000_000e18;
    uint64 constant T = 100_000;
    bytes32 constant INITIAL = bytes32(uint256(1));
    bytes32 constant LATE = bytes32(uint256(99));
    address constant INVESTOR = address(11);
    address constant FOUNDATION = address(22);
    address constant GUARDIAN = address(33);
    LIFEToken token;
    LIFEVestingVault vault;
    TGERegistry registry;
    LIFEEmissionVault emission;
    TGEDistributionVault distribution;
    LIFEUpgradeTimelock lock;

    function setUp() public {
        vm.warp(T);
        token = new LIFEToken(address(this));
        lock = new LIFEUpgradeTimelock(address(this));
        LIFEVestingVault implementation = new LIFEVestingVault();
        vault = LIFEVestingVault(address(new ERC1967Proxy(address(implementation), abi.encodeCall(
            LIFEVestingVault.initialize,
            (LIFEVestingVault.InitParams(token, address(this), FOUNDATION, address(lock), GUARDIAN))
        ))));
        registry = new TGERegistry(address(this), address(vault));
        emission = new LIFEEmissionVault(token, registry, address(111));
        distribution = new TGEDistributionVault(token, registry, address(this));
        vault.configure(registry, emission, distribution);
        token.transfer(address(vault), BUDGET);
        token.transfer(address(emission), 3_100_000_000e18);
        token.transfer(address(distribution), 1_900_000_000e18);
        distribution.setAllocation(address(115), 1_900_000_000e18);
        distribution.seal();
        assertEq(vault.createGrant(0, INVESTOR, 480e18), INITIAL);
        assertEq(vault.createGrant(2, address(113), vault.cap(2)), bytes32(uint256(2)));
        assertEq(vault.createGrant(3, address(114), vault.cap(3)), bytes32(uint256(3)));
    }

    function launch() internal { vault.seal(); registry.setTGE(T); }
    function add(uint8 category, uint256 amount, uint64 start) internal {
        vault.createGrantWithStart(LATE, category, INVESTOR, amount, start);
    }

    function test_PartialAndZeroRevocableBudgetsLaunch() public {
        launch();
        assertTrue(vault.isReady());
        assertEq(vault.remainingBudget(0), vault.cap(0) - 480e18);
        assertEq(vault.remainingBudget(1), vault.cap(1));
        assertEq(vault.grantStart(INITIAL), T);
    }

    function test_FullBudgetBackingRequiredAtCreationSealAndReadiness() public {
        deal(address(token), address(vault), BUDGET - 1);
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector);
        vault.createGrant(1, INVESTOR, 1);
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector); vault.seal();
        deal(address(token), address(vault), BUDGET); launch();
        deal(address(token), address(vault), BUDGET - 1);
        assertFalse(vault.isReady());
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector); add(1, 1, T);
    }

    function test_GuardsStateTimeAndAuthority() public {
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); add(0, 1, T);
        vault.seal();
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); add(0, 1, T);
        registry.setTGE(T + 100);
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); add(0, 1, T + 100);
        vm.warp(T + 100);
        vm.prank(address(777)); vm.expectRevert(LIFEVestingVault.Unauthorized.selector); add(0, 1, T + 100);
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); add(0, 1, T + 99);
        vm.prank(GUARDIAN); vault.pause();
        vm.expectRevert(); add(0, 1, T + 100);
    }

    function test_GuardsCategoriesIdsAmountsAndRecipients() public {
        launch();
        for (uint8 i = 2; i < 5; ++i) {
            vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); add(i, 1, T);
        }
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); add(0, 0, T);
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector);
        vault.createGrantWithStart(bytes32(0), 0, INVESTOR, 1, T);
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector);
        vault.createGrantWithStart(INITIAL, 0, INVESTOR, 1, T);
        address[8] memory forbidden = [address(0), address(vault), address(token), address(lock), address(registry), address(emission), address(distribution), FOUNDATION];
        for (uint256 i; i < forbidden.length; ++i) {
            vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
            vault.createGrantWithStart(LATE, 0, forbidden[i], 1, T);
        }
        add(0, 1, T);
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); add(1, 1, T);
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); vault.createGrant(0, INVESTOR, 1);
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); vault.seal();
    }

    function test_IndependentStartsAndBoundaries() public {
        launch(); vm.warp(T + 60 * 30 days);
        uint64 start = uint64(block.timestamp + 30 days);
        add(0, 480e18, start);
        vault.createGrantWithStart(bytes32(uint256(100)), 1, INVESTOR, 480e18, start + 30 days);
        assertEq(vault.grantStart(LATE), start);
        assertEq(vault.vestedAt(INITIAL, uint64(block.timestamp)), 480e18);
        assertEq(vault.vestedAt(LATE, T - 1), 0);
        assertEq(vault.vestedAt(LATE, start - 1), 0);
        assertEq(vault.vestedAt(LATE, start), 0);
        assertEq(vault.vestedAt(LATE, start + 12 * 30 days), 0);
        assertEq(vault.vestedAt(LATE, start + 13 * 30 days), 10e18);
        assertEq(vault.vestedAt(bytes32(uint256(100)), start + 13 * 30 days), 0);
        assertEq(vault.vestedAt(LATE, start + 60 * 30 days), 480e18);
        assertEq(vault.vestedAt(LATE, start + 61 * 30 days), 480e18);
    }

    function test_StartPersistsAcrossUpgradeAndFutureStartCannotPay() public {
        launch(); uint64 start = T + 100 days; add(1, 480e18, start);
        assertEq(vault.claim(LATE, LIFEVestingVault.Account.Investor), 0);
        vm.prank(GUARDIAN); vault.pause();
        LIFEVestingVault next = new LIFEVestingVault();
        vm.prank(address(lock)); vault.upgradeToAndCall(address(next), "");
        assertEq(vault.grantStart(LATE), start);
        assertEq(vault.remainingBudget(1), vault.cap(1) - 480e18);
        vm.prank(address(lock)); vault.unpause();
        vm.warp(start + 13 * 30 days);
        assertEq(vault.claim(LATE, LIFEVestingVault.Account.Investor), 10e18);
        assertTrue(vault.isReady());
    }

    function test_InvalidGetterIdsAndCategories() public {
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); vault.grantStart(LATE);
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); vault.remainingBudget(4);
        assertEq(vault.grantStart(INITIAL), 0);
        assertEq(vault.vestedAt(INITIAL, T + 60 * 30 days), 0);
    }

    function test_ExactReserveIsAssignableOnceAndNeverReopens() public {
        launch(); uint256 reserve = vault.remainingBudget(0);
        vm.expectRevert(LIFEVestingVault.AllocationExceeded.selector); add(0, reserve + 1, T);
        add(0, reserve, T);
        vm.warp(T + 60 * 30 days); vault.claim(LATE, LIFEVestingVault.Account.Investor);
        assertEq(vault.remainingBudget(0), 0);
        assertEq(token.balanceOf(address(vault)), BUDGET - vault.system().totalPaid);
        assertTrue(vault.isReady());
        deal(address(token), address(vault), BUDGET);
        vm.expectRevert(LIFEVestingVault.AllocationExceeded.selector);
        vault.createGrantWithStart(bytes32(uint256(100)), 0, INVESTOR, 1, uint64(block.timestamp));
    }

    function testFuzz_ReserveConservation(uint256 amount, bool reclaim) public {
        launch(); amount = bound(amount, 48, vault.remainingBudget(0));
        uint64 start = T + 30 days; add(0, amount, start);
        vm.warp(start + 13 * 30 days);
        vault.redirectToFoundation(LATE, reclaim, bytes32(0));
        vm.warp(start + 14 * 30 days);
        vault.restoreFutureToInvestor(LATE, bytes32(0));
        vm.prank(INVESTOR); vault.proposeWalletChange(LATE, LIFEVestingVault.Account.Investor, address(55));
        vm.prank(address(55)); vault.acceptWalletChange(LATE, LIFEVestingVault.Account.Investor, 1);
        vault.claim(LATE, LIFEVestingVault.Account.Investor);
        vault.claim(LATE, LIFEVestingVault.Account.Foundation);
        LIFEVestingVault.Grant memory g = vault.details(LATE);
        assertEq(g.paid, amount * 2 / 48);
        assertEq(token.balanceOf(FOUNDATION), reclaim ? amount * 2 / 48 : amount * 2 / 48 - amount / 48);
        assertEq(g.credit[0] + g.credit[1], 0);
        assertEq(vault.grantStart(LATE), start);
        assertEq(vault.remainingBudget(0) + vault.system().allocated[0], vault.cap(0));
        uint256 allReserves;
        for (uint8 i; i < 4; ++i) allReserves += vault.remainingBudget(i);
        assertEq(vault.system().totalAllocated - vault.system().totalPaid + allReserves, BUDGET - vault.system().totalPaid);
        assertEq(token.balanceOf(address(vault)), BUDGET - vault.system().totalPaid);
        assertEq(vault.claim(LATE, LIFEVestingVault.Account.Investor), 0);
    }

    function test_LegacyUpgradePreservesLayoutAndCannotManufactureReserve() public {
        token = new LIFEToken(address(this));
        LegacyLIFEVestingVault oldImplementation = new LegacyLIFEVestingVault();
        LegacyLIFEVestingVault old = LegacyLIFEVestingVault(address(new ERC1967Proxy(address(oldImplementation), abi.encodeCall(
            LegacyLIFEVestingVault.initialize,
            (LegacyLIFEVestingVault.InitParams(token, address(this), FOUNDATION, address(lock), GUARDIAN))
        ))));
        vault = LIFEVestingVault(address(old));
        registry = new TGERegistry(address(this), address(old));
        emission = new LIFEEmissionVault(token, registry, address(111));
        distribution = new TGEDistributionVault(token, registry, address(this));
        old.configure(registry, emission, distribution);
        token.transfer(address(old), BUDGET);
        token.transfer(address(emission), 3_100_000_000e18);
        token.transfer(address(distribution), 1_900_000_000e18);
        distribution.setAllocation(address(115), 1_900_000_000e18); distribution.seal();
        for (uint8 i; i < 4; ++i) old.createGrant(bytes32(uint256(i + 1)), i, address(uint160(200 + i)), old.cap(i));
        old.seal(); registry.setTGE(T);
        vm.warp(T + 13 * 30 days);
        old.claim(INITIAL, LegacyLIFEVestingVault.Account.Investor);
        old.redirectToFoundation(INITIAL, false, bytes32(0));
        LIFEVestingVault previouslyProposed = new LIFEVestingVault();
        vm.prank(address(200)); old.proposeWalletChange(INITIAL, LegacyLIFEVestingVault.Account.Investor, address(previouslyProposed));
        old.proposeGovernance(address(777));
        bytes32 grantHash = keccak256(abi.encode(old.details(INITIAL)));
        bytes32 systemHash = keccak256(abi.encode(old.system()));
        vm.prank(GUARDIAN); old.pause();
        LIFEVestingVault next = new LIFEVestingVault();
        bytes memory upgrade = abi.encodeCall(old.upgradeToAndCall, (address(next), bytes("")));
        lock.schedule(address(old), 0, upgrade, bytes32(0), "legacy", 48 hours);
        vm.warp(block.timestamp + 48 hours);
        lock.execute(address(old), 0, upgrade, bytes32(0), "legacy");
        assertEq(keccak256(abi.encode(vault.details(INITIAL))), grantHash);
        assertEq(keccak256(abi.encode(vault.system())), systemHash);
        assertTrue(vault.paused());
        assertEq(vault.grantStart(INITIAL), T);
        assertEq(vault.grantIdAt(0), INITIAL);
        for (uint8 i; i < 4; ++i) assertEq(vault.remainingBudget(i), 0);
        // Old implementation and wallet proposal history still protect implementation selection.
        vm.prank(address(lock)); vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        vault.upgradeToAndCall(address(oldImplementation), "");
        vm.prank(address(lock)); vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        vault.upgradeToAndCall(address(previouslyProposed), "");
        vm.prank(address(lock)); vault.unpause();
        vm.expectRevert(LIFEVestingVault.AllocationExceeded.selector);
        add(0, 1, uint64(block.timestamp));
        vm.prank(address(previouslyProposed)); vault.acceptWalletChange(INITIAL, LIFEVestingVault.Account.Investor, 1);
        assertEq(vault.details(INITIAL).wallets[0], address(previouslyProposed));
        assertEq(vault.grantStart(INITIAL), T);
    }
}
