// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LIFEVestingVaultTest} from "./LIFEVestingVault.t.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";

contract VestingEntitlementTest is LIFEVestingVaultTest {
    function initialClaim() internal {
        vm.warp(T + 20 * 30 days);
        vault.claim(ID, LIFEVestingVault.Account.Investor);
        vm.warp(T + 24 * 30 days);
    }

    function test_RedirectPreservesEarnedCredit() public {
        initialClaim();
        vault.redirectToFoundation(ID, false, "end");
        assertEq(vault.details(ID).credit[0], 40e18);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 40e18);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 0);
        vm.warp(T + 60 * 30 days);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 240e18);
        assertEq(vault.details(ID).paid, 480e18);
    }

    function test_ReclaimOnlyUnclaimedCredit() public {
        initialClaim();
        vault.redirectToFoundation(ID, true, "end");
        assertEq(vault.details(ID).credit[0], 0);
        assertEq(vault.details(ID).credit[1], 40e18);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 40e18);
        assertEq(token.balanceOf(investor), 200e18);
    }

    function test_RestoreIsProspective() public {
        initialClaim();
        vault.redirectToFoundation(ID, false, "end");
        vm.warp(T + 30 * 30 days);
        vault.restoreFutureToInvestor(ID, "restore");
        assertEq(vault.details(ID).credit[1], 60e18);
        assertEq(vault.details(ID).credit[0], 40e18);
        vm.warp(T + 31 * 30 days);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 50e18);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 60e18);
    }

    function test_ClaimBeforeRedirectCannotBeRecovered() public {
        initialClaim();
        vault.claim(ID, LIFEVestingVault.Account.Investor);
        vault.redirectToFoundation(ID, true, "end");
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 0);
        assertEq(token.balanceOf(investor), 240e18);
    }

    function test_EntitlementAuthorizationAndState() public {
        vm.prank(investor);
        vm.expectRevert();
        vault.redirectToFoundation(ID, true, "end");
        vm.expectRevert();
        vault.restoreFutureToInvestor(ID, "restore");
        vault.redirectToFoundation(ID, false, "end");
        vm.expectRevert();
        vault.redirectToFoundation(ID, false, "end");
        vm.prank(investor);
        vm.expectRevert();
        vault.restoreFutureToInvestor(ID, "restore");
        vm.expectRevert();
        vault.redirectToFoundation(bytes32(uint256(3)), true, "end");
        vm.expectRevert();
        vault.restoreFutureToInvestor(bytes32(uint256(3)), "restore");
    }

    function test_WalletRotationPreservesRights() public {
        initialClaim();
        vm.prank(investor);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(44));
        vm.prank(address(44));
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 40e18);
        assertEq(token.balanceOf(address(44)), 40e18);
        assertEq(token.balanceOf(investor), 200e18);
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(45));
    }

    function test_WalletNonceCancelAndCollision() public {
        vm.prank(investor);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(44));
        vm.prank(investor);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(45));
        vm.prank(address(44));
        vm.expectRevert();
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        vm.prank(address(45));
        vm.expectRevert();
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        vm.prank(investor);
        vault.cancelWalletChange(ID, LIFEVestingVault.Account.Investor, 2);
        vm.prank(address(45));
        vm.expectRevert();
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 2);
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, foundation);
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(0));
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(vault));
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(token));
        vm.prank(investor);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(55));
        vm.prank(foundation);
        vault.proposeWalletChange(ID, LIFEVestingVault.Account.Foundation, address(55));
        vm.prank(address(55));
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Foundation, 1);
        vm.prank(address(55));
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);
        vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 3);
    }

    function test_GovernanceHandover() public {
        vm.expectRevert();
        vault.proposeGovernance(address(0));
        vm.expectRevert();
        vault.proposeGovernance(guardian);
        vm.prank(investor);
        vm.expectRevert();
        vault.proposeGovernance(address(66));
        vault.proposeGovernance(address(66));
        vm.prank(investor);
        vm.expectRevert();
        vault.acceptGovernance();
        vm.prank(address(66));
        vault.acceptGovernance();
        vm.expectRevert();
        vault.redirectToFoundation(ID, false, "end");
        vm.prank(address(66));
        vault.redirectToFoundation(ID, false, "end");
        assertEq(uint256(vault.details(ID).futureRecipient), 1);
    }
}
