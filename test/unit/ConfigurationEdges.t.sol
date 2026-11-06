// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {VestingUpgradeTest} from "../integration/VestingUpgrade.t.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
contract ConfigurationEdgesTest is VestingUpgradeTest {
    function test_InitRoleValidationAndGetters() public {
        LIFEVestingVault.InitParams memory p=params(1,true);p.governance=address(0);vm.expectRevert();deploy(p);
        p=params(1,true);p.emergencyPauser=address(0);vm.expectRevert();deploy(p);
        p=params(1,true);p.emergencyPauser=p.governance;vm.expectRevert();deploy(p);

        assertEq(vault.details(ID).allocation,480e18);assertEq(vault.details(ID).settledVested,0);assertTrue(vault.details(ID).revocable);
        assertEq(vault.system().upgradeTimelock,address(lock));assertEq(vault.system().emergencyPauser,guardian);
        assertEq(vault.vestedAt(ID, T+24*30 days),120e18);
    }
    function test_CancelRequiresCurrentWalletAndNonce() public {
        vm.expectRevert();vault.cancelWalletChange(ID, LIFEVestingVault.Account.Investor,1);
        vm.prank(investor);vm.expectRevert();vault.cancelWalletChange(ID, LIFEVestingVault.Account.Investor,1);
        vm.prank(investor);vault.proposeWalletChange(ID, LIFEVestingVault.Account.Investor,address(55));
        vm.prank(investor);vm.expectRevert();vault.cancelWalletChange(ID, LIFEVestingVault.Account.Investor,2);
    }
    function test_PauserRotationViaTimelock() public {
        vm.expectRevert();vault.setEmergencyPauser(address(77));
        bytes memory bad=abi.encodeCall(vault.setEmergencyPauser,(address(0)));queue(address(vault),bad,"bad");
        vm.warp(block.timestamp+48 hours);vm.expectRevert();execute(address(vault),bad,"bad");
        bytes memory data=abi.encodeCall(vault.setEmergencyPauser,(address(77)));queue(address(vault),data,"new");
        vm.warp(block.timestamp+48 hours);execute(address(vault),data,"new");assertEq(vault.system().emergencyPauser,address(77));
        vm.prank(guardian);vm.expectRevert();vault.pause();vm.prank(address(77));vault.pause();assertTrue(vault.paused());
        vm.expectRevert();vault.proposeGovernance(address(77));
    }
    function test_CancelUpgradeAndCalldataBinding() public {
        bytes memory data=abi.encodeCall(vault.unpause,());queue(address(vault),data,"cancel");
        bytes32 id=lock.hashOperation(address(vault),0,data,bytes32(0),"cancel");lock.cancel(id);
        vm.warp(block.timestamp+48 hours);vm.expectRevert();execute(address(vault),data,"cancel");
        queue(address(vault),data,"queued");vm.warp(block.timestamp+48 hours);
        vm.expectRevert();execute(address(vault),abi.encodeCall(vault.pause,()),"queued");
        vm.expectRevert();execute(address(vault),data,"different");
    }
}
