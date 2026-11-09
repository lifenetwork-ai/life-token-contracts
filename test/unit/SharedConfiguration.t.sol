// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LaunchTest} from "../integration/Launch.t.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";
contract SharedConfigurationTest is LaunchTest {
    function test_SealTwiceRejected() public {fund();vm.expectRevert();f.seal();}
    function test_SharedInvalidInitializerAndConfiguration() public {
        LIFEVestingVault other=LIFEVestingVault(address(new ERC1967Proxy(address(impl), abi.encodeCall(LIFEVestingVault.initialize, (LIFEVestingVault.InitParams(t,address(this),address(22),address(lock),address(33)))))));
        vm.prank(address(99));vm.expectRevert();other.configure(r,e,d);
        vm.expectRevert();other.configure(TGERegistry(address(0)),e,d);
        vm.expectRevert();other.configure(r,e,d);
        TGERegistry own=new TGERegistry(address(this),address(other));
        vm.expectRevert();other.configure(own,e,d);
        LIFEEmissionVault ee=new LIFEEmissionVault(t,own,address(44));TGEDistributionVault dd=new TGEDistributionVault(t,own,address(this));other.configure(own,ee,dd);
        assertFalse(other.isReady());vm.expectRevert();other.seal();
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector);other.createGrant(0,address(11),1);
        vm.prank(address(99));vm.expectRevert();other.seal();
        assertEq(other.cap(0),2_000_000_000e18);assertEq(other.cap(1),500_000_000e18);assertEq(other.cap(2),800_000_000e18);assertEq(other.cap(3),1_000_000_000e18);assertEq(other.cap(4),700_000_000e18);
        vm.expectRevert();other.cap(5);vm.prank(address(99));vm.expectRevert();d.seal();
    }

    function test_GrantInputInventoryAndPauseGuards() public {
        t.transfer(address(f),5_000_000_000e18);
        vm.expectRevert();f.createGrant(0,address(11),0);
        address[7] memory bad=[address(0),address(f),address(t),address(lock),address(r),address(e),address(d)];
        for(uint256 i;i<bad.length;++i){vm.expectRevert();f.createGrant(0,bad[i],1);}
        vm.expectRevert();f.createGrant(0,address(22),1);
        assertEq(f.system().grantCount,0);assertEq(f.system().totalAllocated,0);
        bytes32 first=f.createGrant(0,address(11),1);bytes32 second=f.createGrant(0,address(11),1);
        assertTrue(first!=second);
        assertEq(f.grantIdAt(0),first);assertEq(f.grantIdAt(1),second);
        vm.expectRevert();f.grantIdAt(2);
        vm.expectRevert();f.details("missing");vm.expectRevert();f.claimable("missing",LIFEVestingVault.Account.Investor);
        vm.expectRevert();f.vestedAt("missing",T);vm.expectRevert();f.claim("missing",LIFEVestingVault.Account.Foundation);
        vm.prank(address(33));f.pause();assertFalse(f.isReady());
        vm.expectRevert();f.createGrant(0,address(11),1);vm.expectRevert();f.seal();vm.expectRevert();f.configure(r,e,d);
        f.proposeGovernance(address(88));vm.prank(address(88));f.acceptGovernance();assertEq(f.system().governance,address(88));
    }
    function test_ReadinessRequiresEveryFundedModule() public {
        fund();assertTrue(f.isReady());
        deal(address(t),address(e),0);assertFalse(f.isReady());deal(address(t),address(e),3_100_000_000e18);
        deal(address(t),address(d),0);assertFalse(f.isReady());deal(address(t),address(d),1_900_000_000e18);
        vm.prank(address(33));f.pause();assertFalse(f.isReady());vm.expectRevert();r.setTGE(T);
    }

    function test_SealRequiresOutstandingFunds() public {
        t.transfer(address(f),5_000_000_000e18);
        for(uint8 i;i<5;++i)assertEq(f.createGrant(i,recipients[i],f.cap(i)),bytes32(uint256(i+1)));
        deal(address(t),address(f),5_000_000_000e18-1);
        vm.expectRevert(LIFEVestingVault.InsufficientFunding.selector);f.seal();assertFalse(f.system().isSealed);
    }
    function test_ConfigureRejectsRecoveryWalletThatBecomesModule() public {
        address predictedRegistry=vm.computeCreateAddress(address(this),vm.getNonce(address(this))+1);
        LIFEVestingVault other=LIFEVestingVault(address(new ERC1967Proxy(address(impl),abi.encodeCall(LIFEVestingVault.initialize,(LIFEVestingVault.InitParams(t,address(this),predictedRegistry,address(lock),address(33)))))));
        TGERegistry own=new TGERegistry(address(this),address(other));assertEq(address(own),predictedRegistry);
        LIFEEmissionVault ee=new LIFEEmissionVault(t,own,address(44));TGEDistributionVault dd=new TGEDistributionVault(t,own,address(this));
        vm.expectRevert(LIFEVestingVault.InvalidConfiguration.selector);other.configure(own,ee,dd);
        assertEq(address(other.system().registry),address(0));
    }
}
