// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {LateGrantsTest} from "./LateGrants.t.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";

// Interface keeps the RED phase executable before the production overloads exist.
interface IAutoGrantIds {
    function nextGrantId() external view returns (bytes32);
    function createGrant(uint8 category, address beneficiary, uint256 amount) external returns (bytes32);
    function createGrantWithStart(uint8 category, address beneficiary, uint256 amount, uint64 start) external returns (bytes32);
}

contract AutoGrantIdsTest is LateGrantsTest {
    function test_LegacyInitialSelectorIsAbsent() public {
        (bool ok,) = address(vault).call(abi.encodeWithSignature(
            "createGrant(bytes32,uint8,address,uint256)", bytes32(uint256(900)), uint8(0), INVESTOR, uint256(1)
        ));
        assertFalse(ok, "legacy manual initial selector must be absent");
    }
    function autoVault() internal view returns (IAutoGrantIds) { return IAutoGrantIds(address(vault)); }

    function test_AutoFreshProxyStartsAtOne() public {
        LIFEVestingVault fresh = LIFEVestingVault(address(new ERC1967Proxy(address(new LIFEVestingVault()), abi.encodeCall(
            LIFEVestingVault.initialize,
            (LIFEVestingVault.InitParams(token, address(this), FOUNDATION, address(lock), GUARDIAN))
        ))));
        assertEq(IAutoGrantIds(address(fresh)).nextGrantId(), bytes32(uint256(1)));
        TGERegistry r = new TGERegistry(address(this), address(fresh));
        LIFEEmissionVault e = new LIFEEmissionVault(token, r, address(111));
        TGEDistributionVault d = new TGEDistributionVault(token, r, address(this));
        fresh.configure(r, e, d);
        deal(address(token), address(fresh), BUDGET);
        assertEq(IAutoGrantIds(address(fresh)).createGrant(0, INVESTOR, 1), bytes32(uint256(1)));
        assertEq(IAutoGrantIds(address(fresh)).createGrant(1, INVESTOR, 2), bytes32(uint256(2)));
        assertEq(fresh.grantIdAt(0), bytes32(uint256(1)));
        assertEq(fresh.grantIdAt(1), bytes32(uint256(2)));
    }

    /// Explicit late-grant IDs may occupy sequence values; automatic IDs skip them without overwriting.
    function test_AutoSkipsExplicitLateIdCollisions() public {
        launch();
        vault.createGrantWithStart(bytes32(uint256(5)), 0, INVESTOR, 1, T);
        bytes32 historical = keccak256("historical reference");
        vault.createGrantWithStart(historical, 1, INVESTOR, 1, T);
        bytes32 explicitHash = keccak256(abi.encode(vault.details(bytes32(uint256(5)))));
        assertEq(autoVault().nextGrantId(), bytes32(uint256(6)));
        assertEq(autoVault().createGrantWithStart(0, INVESTOR, 10, T), bytes32(uint256(6)));
        assertEq(autoVault().nextGrantId(), bytes32(uint256(7)));
        assertEq(keccak256(abi.encode(vault.details(bytes32(uint256(5))))), explicitHash);
        assertEq(vault.details(historical).allocation, 1);
    }

    function test_AutoFailureDoesNotConsumeSequence() public {
        uint256 excessive = vault.cap(1) + 1;
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); autoVault().createGrant(0, INVESTOR, 0);
        vm.expectRevert(LIFEVestingVault.AllocationExceeded.selector); autoVault().createGrant(1, INVESTOR, excessive);
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector); autoVault().createGrant(0, FOUNDATION, 1);
        deal(address(token), address(vault), BUDGET - 1);
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector); autoVault().createGrant(0, INVESTOR, 1);
        deal(address(token), address(vault), BUDGET);
        assertEq(autoVault().nextGrantId(), bytes32(uint256(5)));
        assertEq(autoVault().createGrant(0, INVESTOR, 1), bytes32(uint256(5)));
    }

    function test_AutoLateRepeatedBeneficiaryHasIndependentIdsAndStarts() public {
        assertEq(autoVault().createGrant(1, INVESTOR, 1), bytes32(uint256(5)));
        launch();
        bytes32 first = autoVault().createGrantWithStart(0, INVESTOR, 48e18, T);
        bytes32 second = autoVault().createGrantWithStart(1, INVESTOR, 96e18, T + 30 days);
        assertEq(first, bytes32(uint256(6))); assertEq(second, bytes32(uint256(7)));
        assertEq(vault.grantStart(first), T); assertEq(vault.grantStart(second), T + 30 days);
        assertEq(vault.vestedAt(first, T + 13 * 30 days), 13e18);
        assertEq(vault.vestedAt(second, T + 13 * 30 days - 1), 0);
        assertEq(vault.vestedAt(second, T + 13 * 30 days), 24e18);
        assertEq(vault.grantIdAt(5), first); assertEq(vault.grantIdAt(6), second);
    }

    function test_AutoPhaseAuthorityPauseAndTimeGuards() public {
        vm.prank(address(777)); vm.expectRevert(LIFEVestingVault.Unauthorized.selector); autoVault().createGrant(0, INVESTOR, 1);
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T);
        vault.seal();
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); autoVault().createGrant(0, INVESTOR, 1);
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T);
        registry.setTGE(T + 100);
        vm.expectRevert(LIFEVestingVault.InvalidState.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T + 100);
        vm.warp(T + 100);
        vm.prank(address(777)); vm.expectRevert(LIFEVestingVault.Unauthorized.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T + 100);
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T + 99);
        vm.prank(GUARDIAN); vault.pause();
        vm.expectRevert(); autoVault().createGrant(0, INVESTOR, 1);
        vm.expectRevert(); autoVault().createGrantWithStart(0, INVESTOR, 1, T + 100);
        assertEq(autoVault().nextGrantId(), bytes32(uint256(5)));
    }

    function test_AutoLateReusesCategoryRecipientFundingAndBudgetGuards() public {
        launch();
        for (uint8 category = 2; category < 5; ++category) {
            vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); autoVault().createGrantWithStart(category, INVESTOR, 1, T);
        }
        vm.expectRevert(LIFEVestingVault.InvalidGrant.selector); autoVault().createGrantWithStart(0, INVESTOR, 0, T);
        address[8] memory forbidden = [address(0), address(vault), address(token), address(lock), address(registry), address(emission), address(distribution), FOUNDATION];
        for (uint256 i; i < forbidden.length; ++i) {
            vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector); autoVault().createGrantWithStart(0, forbidden[i], 1, T);
        }
        deal(address(token), address(vault), BUDGET - 1);
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T);
        deal(address(token), address(vault), BUDGET);
        uint256 reserve = vault.remainingBudget(0);
        vm.expectRevert(LIFEVestingVault.AllocationExceeded.selector); autoVault().createGrantWithStart(0, INVESTOR, reserve + 1, T);
        assertEq(autoVault().createGrantWithStart(0, INVESTOR, reserve, T), bytes32(uint256(5)));
        vm.expectRevert(LIFEVestingVault.AllocationExceeded.selector); autoVault().createGrantWithStart(0, INVESTOR, 1, T);
        assertEq(autoVault().nextGrantId(), bytes32(uint256(6)));
    }

    function test_AutoExhaustionHasExplicitErrorAndNeverWraps() public {
        // SystemView occupies 17 slots (allocated[5]); five following fields occupy slots 17..21.
        bytes32 base = keccak256(abi.encode(uint256(keccak256("life.storage.SharedVesting")) - 1)) & ~bytes32(uint256(0xff));
        bytes32 cursorSlot = bytes32(uint256(base) + 22);
        vm.store(address(vault), cursorSlot, bytes32(type(uint256).max - 1));
        assertEq(autoVault().createGrant(0, INVESTOR, 1), bytes32(type(uint256).max - 1));
        assertEq(autoVault().nextGrantId(), bytes32(type(uint256).max));
        assertEq(autoVault().createGrant(0, INVESTOR, 1), bytes32(type(uint256).max));
        vm.expectRevert(bytes4(keccak256("GrantIdExhausted()"))); autoVault().nextGrantId();
        vm.expectRevert(bytes4(keccak256("GrantIdExhausted()"))); autoVault().createGrant(0, INVESTOR, 1);
        vm.store(address(vault), cursorSlot, bytes32(type(uint256).max - 1));
        vm.expectRevert(bytes4(keccak256("GrantIdExhausted()"))); autoVault().nextGrantId();
        assertEq(vault.details(INITIAL).allocation, 480e18);
    }
}
