// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {TGERegistry} from "../../src/TGERegistry.sol";
import {VestingMath} from "../../src/libraries/VestingMath.sol";

contract ReadinessMock {
    bool public ready;

    function setReady(bool r) external {
        ready = r;
    }

    function isRecipientAllowed(address) external pure returns (bool) { return true; }

    function isReady() external view returns (bool) {
        return ready;
    }
}

contract ScheduleTest is Test {
    uint64 constant T = 100000;

    function test_MonthlyBoundariesAndRounding() public pure {
        assertEq(VestingMath.monthlyVested(49, 0, T, 12, 48), 0);
        assertEq(VestingMath.monthlyVested(49, T, T - 1, 12, 48), 0);
        assertEq(VestingMath.monthlyVested(49, T, T + 12 * 30 days, 12, 48), 0);
        assertEq(VestingMath.monthlyVested(49, T, T + 13 * 30 days - 1, 12, 48), 0);
        assertEq(VestingMath.monthlyVested(49, T, T + 13 * 30 days, 12, 48), 1);
        assertEq(VestingMath.monthlyVested(49, T, T + 60 * 30 days, 12, 48), 49);
        assertEq(VestingMath.monthlyVested(120, T, T + 3 * 30 days, 3, 120), 0);
        assertEq(VestingMath.monthlyVested(120, T, T + 4 * 30 days, 3, 120), 1);
        assertEq(VestingMath.monthlyVested(120, T, T + 123 * 30 days, 3, 120), 120);
    }

    function test_EmissionAllBoundaries() public pure {
        assertEq(VestingMath.emissionVested(0, T), 0);
        assertEq(VestingMath.emissionVested(T, T - 1), 0);
        uint256 sum;
        for (uint64 i; i < 80; ++i) {
            uint64 at = T + (48 + 3 * i) * 30 days;
            assertEq(VestingMath.emissionVested(T, at - 1), sum);
            sum += 100_000_000e18 / (2 ** (i / 16));
            assertEq(VestingMath.emissionVested(T, at), sum);
            assertEq(VestingMath.emissionVested(T, at + 1), sum);
        }
        assertEq(sum, 3_100_000_000e18);
        assertEq(VestingMath.emissionVested(T, type(uint64).max), sum);
    }

    function testFuzz_MonthlyConservation(uint96 amount, uint16 month) public pure {
        uint256 v = VestingMath.monthlyVested(amount, T, uint64(T + uint256(month) * 30 days), 12, 48);
        assertLe(v, amount);
        if (month >= 60) assertEq(v, amount);
    }

    function test_TGEAndGovernance() public {
        vm.warp(T);
        ReadinessMock r = new ReadinessMock();
        TGERegistry g = new TGERegistry(address(this), address(r));
        assertEq(g.tge(), 0);
        vm.expectRevert();
        g.setTGE(T);
        r.setReady(true);
        vm.expectRevert();
        g.setTGE(0);
        vm.expectRevert();
        g.setTGE(T - 1);
        vm.prank(address(8));
        vm.expectRevert();
        g.setTGE(T);
        g.setTGE(T);
        assertEq(g.tge(), T);
        vm.expectRevert();
        g.setTGE(T + 1);
        vm.expectRevert();
        g.transferOwnership(address(0));
        vm.expectRevert();
        g.renounceOwnership();
        g.transferOwnership(address(9));
        vm.prank(address(8));
        vm.expectRevert();
        g.acceptOwnership();
        vm.prank(address(9));
        g.acceptOwnership();
        assertEq(g.owner(), address(9));
    }

    function test_InvalidRegistryConfig() public {
        vm.expectRevert();
        new TGERegistry(address(0), address(1));
        vm.expectRevert();
        new TGERegistry(address(this), address(0));
        vm.expectRevert();
        new TGERegistry(address(this), address(1));
    }
}
