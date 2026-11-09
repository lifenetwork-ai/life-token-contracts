// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {LIFEEmissionVault} from "../../src/LIFEEmissionVault.sol";
import {TGEDistributionVault} from "../../src/TGEDistributionVault.sol";
import {LIFEUpgradeTimelock} from "../../src/LIFEUpgradeTimelock.sol";
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";
import {LIFEToken} from "../../src/LIFEToken.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

contract LateGrantHandler is Test {
    LIFEToken t; LIFEVestingVault f; TGERegistry r; LIFEEmissionVault e; TGEDistributionVault d;
    uint64 constant T=100000;
    struct Ledger { bytes32 id; uint8 category; uint64 start; uint256 allocation; uint256 seen; uint256 paid; uint256[2] credits; bool redirected; }
    Ledger[] private ledgers;
    uint256 public donated;
    function setupPool() external {
        t=new LIFEToken(address(this));
        LIFEUpgradeTimelock lock=new LIFEUpgradeTimelock(address(this));
        f=LIFEVestingVault(address(new ERC1967Proxy(address(new LIFEVestingVault()),abi.encodeCall(LIFEVestingVault.initialize,(LIFEVestingVault.InitParams(t,address(this),address(22),address(lock),address(33)))))));
        r=new TGERegistry(address(this),address(f));e=new LIFEEmissionVault(t,r,address(44));d=new TGEDistributionVault(t,r,address(this));f.configure(r,e,d);
        t.transfer(address(f),5_000_000_000e18);
        t.transfer(address(e),3_100_000_000e18);
        t.transfer(address(d),1_900_000_000e18);
        assertEq(f.createGrant(2,address(13),800_000_000e18),bytes32(uint256(1)));
        assertEq(f.createGrant(3,address(14),1_000_000_000e18),bytes32(uint256(2)));
        assertEq(f.createGrant(4,address(15),700_000_000e18),bytes32(uint256(3)));
        f.seal();d.setAllocation(address(55),1_900_000_000e18);d.seal();r.setTGE(T);
    }
    function vault() external view returns(LIFEVestingVault){ return f; }
    function token() external view returns(LIFEToken){ return t; }
    function count() external view returns(uint256){ return ledgers.length; }
    function model(uint256 i) external view returns(Ledger memory){ return ledgers[i]; }
    function create(uint8 categorySeed,uint256 amountSeed,uint32 delaySeed) external {
        if(ledgers.length==32)return;
        uint8 category=categorySeed%2;uint256 available=f.remainingBudget(category);if(available==0)return;
        uint256 amount=bound(amountSeed,1,available);
        uint64 start=uint64(block.timestamp+bound(delaySeed,0,60 days));
        bytes32 id=bytes32(ledgers.length+100);
        f.createGrantWithStart(id,category,address(11),amount,start);
        ledgers.push(Ledger(id,category,start,amount,0,0,[uint256(0),uint256(0)],false));
    }
    function advance(uint32 step) external {vm.warp(block.timestamp+bound(step,0,180 days));}
    function earned(uint256 i) public view returns(uint256 result){
        Ledger storage l=ledgers[i];uint256 carry;
        for(uint256 k=1;k<=48;++k){if(block.timestamp<uint256(l.start)+(k<12?12:k)*30 days)break;result+=l.allocation/48;carry+=l.allocation%48;if(carry>=48){++result;carry-=48;}}
    }
    function settle(uint256 i) private {Ledger storage l=ledgers[i];uint256 v=earned(i);l.credits[l.redirected?1:0]+=v-l.seen;l.seen=v;}
    function claim(uint256 seed,bool foundation) external {
        if(ledgers.length==0)return;uint256 i=seed%ledgers.length;settle(i);Ledger storage l=ledgers[i];uint256 a=foundation?1:0;
        uint256 expected=l.credits[a];assertEq(f.claim(l.id,LIFEVestingVault.Account(a)),expected);l.paid+=expected;l.credits[a]=0;
    }
    function redirect(uint256 seed,bool reclaim) external {
        if(ledgers.length==0)return;uint256 i=seed%ledgers.length;Ledger storage l=ledgers[i];if(l.redirected)return;settle(i);
        f.redirectToFoundation(l.id,reclaim,"late-invariant");if(reclaim){l.credits[1]+=l.credits[0];l.credits[0]=0;}l.redirected=true;
    }
    function restore(uint256 seed) external {
        if(ledgers.length==0)return;uint256 i=seed%ledgers.length;Ledger storage l=ledgers[i];if(!l.redirected)return;settle(i);f.restoreFutureToInvestor(l.id,"late-invariant");l.redirected=false;
    }
    function donate(uint256 seed) external {uint256 balance=t.balanceOf(address(11));if(balance==0)return;uint256 amount=bound(seed,0,balance);vm.prank(address(11));t.transfer(address(f),amount);donated+=amount;}
}
contract LateGrantsInvariantTest is StdInvariant,Test {
    LateGrantHandler h;
    function setUp() public {
        vm.warp(100000);h=new LateGrantHandler();h.setupPool();
        bytes4[] memory selectors=new bytes4[](6);selectors[0]=h.create.selector;selectors[1]=h.advance.selector;selectors[2]=h.claim.selector;selectors[3]=h.redirect.selector;selectors[4]=h.restore.selector;selectors[5]=h.donate.selector;
        targetContract(address(h));targetSelector(FuzzSelector(address(h),selectors));
    }
    function invariant_LateGrantsReserveAndIndependentOracle() public view {
        LIFEVestingVault v=h.vault();uint256 assigned=2_500_000_000e18;uint256 paid;uint256[2] memory categories;
        for(uint256 i;i<h.count();++i){
            LateGrantHandler.Ledger memory l=h.model(i);LIFEVestingVault.Grant memory g=v.details(l.id);
            assertEq(v.grantStart(l.id),l.start);assertEq(g.allocation,l.allocation);assertEq(g.paid,l.paid);assertEq(g.settledVested,l.seen);
            assertEq(g.credit[0],l.credits[0]);assertEq(g.credit[1],l.credits[1]);assertEq(g.paid+g.credit[0]+g.credit[1],g.settledVested);
            assertEq(v.vestedAt(l.id,uint64(block.timestamp)),h.earned(i));
            for(uint256 a;a<2;++a)assertEq(v.claimable(l.id,LIFEVestingVault.Account(a)),l.credits[a]+((l.redirected?1:0)==a?h.earned(i)-l.seen:0));
            assigned+=l.allocation;paid+=l.paid;categories[l.category]+=l.allocation;
        }
        assertEq(v.system().totalAllocated,assigned);assertEq(v.system().totalPaid,paid);
        assertEq(v.remainingBudget(0)+categories[0],v.cap(0));assertEq(v.remainingBudget(1)+categories[1],v.cap(1));
        uint256 reserve=v.remainingBudget(0)+v.remainingBudget(1);
        assertEq((assigned-paid)+reserve,5_000_000_000e18-paid);
        assertEq(h.token().balanceOf(address(v))+paid,5_000_000_000e18+h.donated());
    }
}
