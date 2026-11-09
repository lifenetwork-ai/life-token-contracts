// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LaunchTest} from "./Launch.t.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEVestingVaultV2} from "../fixtures/LIFEVestingVaultV2.sol";
contract FullLifecycleTest is LaunchTest {
    bytes32[5] snapshots;
    bytes32 systemSnapshot;
    function test_FundedLaunchPauseUpgradeAndFinalClaims() public {
        fund();r.setTGE(T);d.claim(address(55));LIFEVestingVault v=f;
        vm.warp(T+20*30 days);uint256 initial=v.claim(grants[0], LIFEVestingVault.Account.Investor);
        vm.warp(T+24*30 days);v.redirectToFoundation(grants[0], false,"end");uint256 credit=v.details(grants[0]).credit[0];
        LIFEVestingVault other=f;other.redirectToFoundation(grants[1], true,"reclaim");assertEq(other.details(grants[1]).credit[0],0);
        vm.prank(recipients[0]);v.proposeWalletChange(grants[0], LIFEVestingVault.Account.Investor,address(88));
        vm.prank(recipients[1]);v.proposeWalletChange(grants[1],LIFEVestingVault.Account.Investor,address(89));
        for(uint256 i;i<5;++i)snapshots[i]=keccak256(abi.encode(v.details(grants[i])));
        systemSnapshot=keccak256(abi.encode(v.system()));
        vm.prank(address(33));v.pause();bytes32 state=keccak256(abi.encode(v.details(grants[0])));
        bytes32 slot=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 otherState=keccak256(abi.encode(other.details(grants[1])));LIFEVestingVaultV2 next=new LIFEVestingVaultV2();
        bytes memory data=abi.encodeCall(v.upgradeToAndCall,(address(next),bytes("")));
        lock.schedule(address(v),0,data,0,"upgrade",48 hours);vm.warp(block.timestamp+48 hours);lock.execute(address(v),0,data,0,"upgrade");
        assertEq(keccak256(abi.encode(v.details(grants[0]))),state);assertEq(keccak256(abi.encode(other.details(grants[1]))),otherState); assertEq(address(uint160(uint256(vm.load(address(v),slot)))),address(next));assertTrue(v.paused());
        for(uint256 i;i<5;++i)assertEq(keccak256(abi.encode(v.details(grants[i]))),snapshots[i]);
        assertEq(keccak256(abi.encode(v.system())),systemSnapshot);
        bytes memory open=abi.encodeCall(v.unpause,());lock.schedule(address(v),0,open,0,"open",48 hours);vm.warp(block.timestamp+48 hours);lock.execute(address(v),0,open,0,"open");
        vm.prank(address(88));v.acceptWalletChange(grants[0], LIFEVestingVault.Account.Investor,1);assertEq(v.claim(grants[0], LIFEVestingVault.Account.Investor),credit);
        vm.warp(T+30*30 days);v.restoreFutureToInvestor(grants[0], "restore");uint256 foundationRights=v.details(grants[0]).credit[1];
        vm.warp(T+60*30 days);uint256 last=v.claim(grants[0], LIFEVestingVault.Account.Investor);assertEq(v.claim(grants[0], LIFEVestingVault.Account.Foundation),foundationRights);
        assertEq(initial+credit+last+foundationRights,2_000_000_000e18);assertEq(t.balanceOf(address(v)),3_000_000_000e18);
        assertEq(t.totalSupply(),10_000_000_000e18);
    }
}
