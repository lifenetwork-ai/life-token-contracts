// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEUpgradeTimelock} from "../../src/LIFEUpgradeTimelock.sol";
import {LIFEVestingVaultV2} from "../fixtures/LIFEVestingVaultV2.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";

contract VestingHandler is Test {
    LIFEVestingVault public vault;
    LIFEToken public token;
    LIFEUpgradeTimelock public lock;
    uint64 public constant T=100000;
    address public constant GUARD=address(0x300);
    struct Model {uint256 seen;uint256 paid;uint256[2] credit;bool routed;address[2] wallets;address[2] proposed;uint256[2] nonce;}
    Model[4] public models;
    uint256[4] public amounts=[uint256(2_000_000_000e18),500_000_000e18,1_000_000_000e18,1_500_000_000e18];
    uint256 private seq;
    uint256 public donated;
    bool public upgraded;
    constructor() {
        token=new LIFEToken(address(this)); lock=new LIFEUpgradeTimelock(address(this));
        vault=LIFEVestingVault(address(new ERC1967Proxy(address(new LIFEVestingVault()),abi.encodeCall(LIFEVestingVault.initialize,(LIFEVestingVault.InitParams(token,address(this),address(0x200),address(lock),GUARD))))));
        TGERegistry registry=new TGERegistry(address(this),address(vault));
        LIFEEmissionVault emission=new LIFEEmissionVault(token,registry,address(0x400));
        TGEDistributionVault distribution=new TGEDistributionVault(token,registry,address(this));
        vault.configure(registry,emission,distribution);
        token.transfer(address(vault),5_000_000_000e18);
        for(uint8 i;i<4;++i){models[i].wallets[0]=address(0x100);models[i].wallets[1]=i<2?address(0x200):address(0);assertEq(vault.createGrant(i,address(0x100),amounts[i]),bytes32(uint256(i+1)));}
        vault.seal();token.transfer(address(emission),3_100_000_000e18);token.transfer(address(distribution),1_900_000_000e18);
        distribution.setAllocation(address(0x500),1_900_000_000e18);distribution.seal();registry.setTGE(T);
    }
    function model(uint256 i) external view returns(Model memory){return models[i];}
    function earned(uint256 i) public view returns(uint256 value){
        uint256 n=i<2?48:120;uint256 cliff=i<2?12:3;uint256 carry;
        // Independent tranche ledger: carry fractional wei at each scheduled release.
        for(uint256 tranche=1;tranche<=n;++tranche){if(block.timestamp<T+(cliff+tranche)*30 days)break;value+=amounts[i]/n;carry+=amounts[i]%n;if(carry>=n){++value;carry-=n;}}
    }
    function settle(uint256 i) internal {Model storage m=models[i];uint256 v=earned(i);m.credit[m.routed?1:0]+=v-m.seen;m.seen=v;}
    function advance(uint32 dt) external {vm.warp(block.timestamp+bound(dt,0,365 days));}
    function claim(uint8 seed,bool foundation) external {uint256 i=seed%4;uint256 a=foundation&&i<2?1:0;if(vault.paused())return;settle(i);Model storage m=models[i];uint256 expected=m.credit[a];uint256 beforeBalance=token.balanceOf(m.wallets[a]);assertEq(vault.claim(bytes32(i+1),LIFEVestingVault.Account(a)),expected);assertEq(token.balanceOf(m.wallets[a])-beforeBalance,expected);m.paid+=expected;m.credit[a]=0;}
    function redirect(uint8 seed,bool reclaim) external {uint256 i=seed%2;Model storage m=models[i];if(vault.paused()||m.routed)return;settle(i);vault.redirectToFoundation(bytes32(i+1),reclaim,"oracle");if(reclaim){m.credit[1]+=m.credit[0];m.credit[0]=0;}m.routed=true;}
    function restore(uint8 seed) external {uint256 i=seed%2;Model storage m=models[i];if(vault.paused()||!m.routed)return;settle(i);vault.restoreFutureToInvestor(bytes32(i+1),"oracle");m.routed=false;}
    function proposeWallet(uint8 seed,bool foundation) external {uint256 i=seed%4;uint256 a=foundation&&i<2?1:0;if(vault.paused())return;settle(i);Model storage m=models[i];address next=address(uint160(0x10000+(++seq)));vm.prank(m.wallets[a]);vault.proposeWalletChange(bytes32(i+1),LIFEVestingVault.Account(a),next);m.proposed[a]=next;++m.nonce[a];}
    function acceptWallet(uint8 seed,bool foundation) external {uint256 i=seed%4;uint256 a=foundation&&i<2?1:0;Model storage m=models[i];if(vault.paused()||m.proposed[a]==address(0))return;settle(i);vm.prank(m.proposed[a]);vault.acceptWalletChange(bytes32(i+1),LIFEVestingVault.Account(a),m.nonce[a]);m.wallets[a]=m.proposed[a];m.proposed[a]=address(0);}
    function cancelWallet(uint8 seed,bool foundation) external {uint256 i=seed%4;uint256 a=foundation&&i<2?1:0;Model storage m=models[i];if(vault.paused()||m.proposed[a]==address(0))return;settle(i);vm.prank(m.wallets[a]);vault.cancelWalletChange(bytes32(i+1),LIFEVestingVault.Account(a),m.nonce[a]);m.proposed[a]=address(0);}
    function donate(uint8 seed,uint256 requested) external {
        address donor=models[seed%4].wallets[0];
        uint256 balance=token.balanceOf(donor);
        if(balance==0)return;
        uint256 amount=bound(requested,0,balance);
        vm.prank(donor);token.transfer(address(vault),amount);donated+=amount;
    }
    function upgrade() external {
        if(upgraded)return;
        if(!vault.paused()){vm.prank(GUARD);vault.pause();}
        LIFEVestingVaultV2 next=new LIFEVestingVaultV2();
        bytes memory data=abi.encodeWithSignature("upgradeToAndCall(address,bytes)",address(next),bytes(""));
        bytes32 salt=bytes32(++seq);lock.schedule(address(vault),0,data,0,salt,48 hours);
        vm.warp(block.timestamp+48 hours);lock.execute(address(vault),0,data,0,salt);
        assertEq(LIFEVestingVaultV2(address(vault)).version(),2);upgraded=true;
    }
    function emergency(bool open) external {if(!open){if(!vault.paused()){vm.prank(GUARD);vault.pause();}}else if(vault.paused()){bytes memory data=abi.encodeCall(vault.unpause,());bytes32 salt=bytes32(++seq);lock.schedule(address(vault),0,data,0,salt,48 hours);vm.warp(block.timestamp+48 hours);lock.execute(address(vault),0,data,0,salt);}}
}
contract VestingInvariantTest is StdInvariant,Test {
    VestingHandler h;
    function setUp() public {vm.warp(100000);h=new VestingHandler();bytes4[] memory selectors=new bytes4[](10);selectors[0]=h.advance.selector;selectors[1]=h.claim.selector;selectors[2]=h.redirect.selector;selectors[3]=h.restore.selector;selectors[4]=h.proposeWallet.selector;selectors[5]=h.acceptWallet.selector;selectors[6]=h.cancelWallet.selector;selectors[7]=h.emergency.selector;selectors[8]=h.donate.selector;selectors[9]=h.upgrade.selector;targetSelector(FuzzSelector(address(h),selectors));targetContract(address(h));}
    function invariant_PooledSolvencyAndIndependentEntitlementOracle() public view {
        LIFEVestingVault v=h.vault();uint256 totalPaid;
        for(uint256 i;i<4;++i){VestingHandler.Model memory m=h.model(i);LIFEVestingVault.Grant memory g=v.details(bytes32(i+1));
            assertEq(g.allocation,h.amounts(i));assertEq(g.paid,m.paid);assertEq(g.settledVested,m.seen);assertEq(g.credit[0],m.credit[0]);assertEq(g.credit[1],m.credit[1]);assertEq(g.paid+g.credit[0]+g.credit[1],g.settledVested);assertLe(g.paid,h.earned(i));
            for(uint256 a;a<(i<2?2:1);++a){assertEq(g.wallets[a],m.wallets[a]);assertEq(g.proposals[a].wallet,m.proposed[a]);assertEq(g.proposals[a].nonce,m.nonce[a]);assertEq(v.claimable(bytes32(i+1),LIFEVestingVault.Account(a)),m.credit[a]+((m.routed?1:0)==a?h.earned(i)-m.seen:0));}
            totalPaid+=g.paid;
        }
        assertEq(v.system().totalPaid,totalPaid);assertEq(v.system().totalAllocated,5_000_000_000e18);assertEq(h.token().balanceOf(address(v))+totalPaid,5_000_000_000e18+h.donated());assertEq(h.token().totalSupply(),10_000_000_000e18);
    }
}
