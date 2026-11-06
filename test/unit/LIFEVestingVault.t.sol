// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEUpgradeTimelock} from "../../src/LIFEUpgradeTimelock.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";

contract LIFEVestingVaultTest is Test {
    LIFEToken token;
    TGERegistry registry;
    LIFEVestingVault impl;
    LIFEVestingVault vault;
    address investor = address(0x11);
    address foundation = address(0x22);
    address guardian = address(0x33);
    uint64 constant T = 100000;

    LIFEUpgradeTimelock lock;
    LIFEEmissionVault emission;
    TGEDistributionVault distribution;
    bytes32 constant ID = bytes32(uint256(1));
    function params(uint256, bool) internal view returns (LIFEVestingVault.InitParams memory) {
        return LIFEVestingVault.InitParams(token, address(this), foundation, address(lock), guardian);
    }
    function deploy(LIFEVestingVault.InitParams memory p) internal returns (LIFEVestingVault) {
        return LIFEVestingVault(address(new ERC1967Proxy(address(impl), abi.encodeCall(LIFEVestingVault.initialize, (p)))));
    }
    function setUp() public virtual {
        vm.warp(T);
        token = new LIFEToken(address(this));
        lock = new LIFEUpgradeTimelock(address(this));
        impl = new LIFEVestingVault();
        vault = deploy(params(0, false));
        registry = new TGERegistry(address(this), address(vault));
        emission = new LIFEEmissionVault(token, registry, address(111));
        distribution = new TGEDistributionVault(token, registry, address(this));
        vault.configure(registry, emission, distribution);
        token.transfer(address(vault), 5_000_000_000e18);
        assertEq(vault.createGrant(0, investor, 480e18), ID);
        assertEq(vault.createGrant(1, address(112), 500_000_000e18), bytes32(uint256(2)));
        assertEq(vault.createGrant(2, address(113), 1_000_000_000e18), bytes32(uint256(3)));
        assertEq(vault.createGrant(3, address(114), 1_500_000_000e18), bytes32(uint256(4)));
        assertEq(vault.createGrant(0, investor, 2_000_000_000e18 - 480e18), bytes32(uint256(5)));
        vault.seal();
        token.transfer(address(emission), 3_100_000_000e18);
        token.transfer(address(distribution), 1_900_000_000e18);
        distribution.setAllocation(address(115), 1_900_000_000e18);
        distribution.seal();
        registry.setTGE(T);
    }

    function test_ClaimOnlyPaysAccountWallet() public {
        vm.warp(T + 13 * 30 days);
        vm.prank(address(99));
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 10e18);
        assertEq(token.balanceOf(investor), 10e18);
        assertEq(token.balanceOf(address(99)), 0);
        assertEq(vault.details(ID).paid, 10e18);
    }

    function test_ClaimZeroIsNoop() public {
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 0);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Foundation), 0);
    }

    function test_LateClaimAccumulates() public {
        vm.warp(T + 24 * 30 days);
        assertEq(vault.claimable(ID, LIFEVestingVault.Account.Investor), 120e18);
        vault.claim(ID, LIFEVestingVault.Account.Investor);
        assertEq(token.balanceOf(investor), 120e18);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 0);
    }

    function test_ClaimCannotConsumeOtherGrants() public {
        vm.warp(T + 60 * 30 days);
        vault.claim(ID, LIFEVestingVault.Account.Investor);
        assertEq(vault.details(ID).paid, 480e18);
        assertEq(token.balanceOf(address(vault)), 5_000_000_000e18 - 480e18);
        assertEq(vault.system().totalPaid, 480e18);
    }

    function test_CannotClaimBeforeTGE() public {
        vm.warp(T - 1);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 0);
    }

    function test_InitializerLocked() public {
        LIFEVestingVault.InitParams memory p = params(1, true);
        vm.expectRevert();
        impl.initialize(p);
        vm.expectRevert();
        vault.initialize(p);
    }

    function test_NonrevocableAccount() public {
        vm.expectRevert();
        vault.claim(bytes32(uint256(3)), LIFEVestingVault.Account.Foundation);
        vm.warp(T + 123 * 30 days);
        assertEq(vault.claim(bytes32(uint256(3)), LIFEVestingVault.Account.Investor), 1_000_000_000e18);
    }
    function test_UnderfundedRevertsWithoutAccountingChange() public {
        deal(address(token), address(vault), 0);
        vm.warp(T + 60 * 30 days);
        vm.expectRevert(); vault.claim(ID, LIFEVestingVault.Account.Investor);
        assertEq(vault.details(ID).paid, 0);
        assertEq(vault.system().totalPaid, 0);
        assertEq(vault.claimable(ID, LIFEVestingVault.Account.Investor), 480e18);
        assertFalse(vault.isReady());
    }
    function test_InvalidConfiguration() public {
        LIFEVestingVault.InitParams memory p = params(0, true);
        p.token = IERC20(address(0)); vm.expectRevert(); deploy(p);
        p = params(0, true); p.foundationWallet = address(0); vm.expectRevert(); deploy(p);
        p = params(0, true); p.upgradeTimelock = address(5); vm.expectRevert(); deploy(p);
        p = params(0, true); p.foundationWallet = address(token); vm.expectRevert(); deploy(p);
    }
    function test_SameRecipientGrantsHaveIndependentWalletNonces() public {
        bytes32 other = bytes32(uint256(5));
        vm.prank(investor); vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(55));
        vm.prank(investor); vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor, address(56));
        vm.prank(investor); vault.proposeWalletChange(other, LIFEVestingVault.Account.Investor, address(55));
        vm.prank(address(55)); vault.acceptWalletChange(other, LIFEVestingVault.Account.Investor, 1);
        vm.prank(address(56)); vm.expectRevert(); vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 1);
        vm.prank(address(56)); vault.acceptWalletChange(ID, LIFEVestingVault.Account.Investor, 2);
        assertEq(vault.details(ID).wallets[0], address(56));
        assertEq(vault.details(other).wallets[0], address(55));
        vm.warp(T + 60 * 30 days);
        assertEq(vault.claim(ID, LIFEVestingVault.Account.Investor), 480e18);
        assertEq(vault.claim(other, LIFEVestingVault.Account.Investor), 2_000_000_000e18 - 480e18);
    }
}
