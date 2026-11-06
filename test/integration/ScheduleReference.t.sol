// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {VestingMath} from "../../src/libraries/VestingMath.sol";

contract ScheduleReferenceTest is Test {
    function test_AllWorkbookMonthsAndSecondBoundaries() public view {
        string memory raw = vm.readFile("test/reference/schedule.json");
        string[4] memory names = [string("investors"), "advisors", "foundation", "ecosystem"];
        uint256[4] memory allocations = [uint256(2_000_000_000e18), 500_000_000e18, 1_000_000_000e18, 1_500_000_000e18];
        uint64 tge = 100000;
        for (uint256 g; g < 4; ++g) {
            uint256[] memory values = vm.parseJsonUintArray(raw, string.concat(".", names[g]));
            assertEq(values.length, 289);
            for (uint64 m; m < 289; ++m) {
                uint64 ts = tge + m * 30 days;
                assertEq(VestingMath.monthlyVested(allocations[g], tge, ts, g < 2 ? 12 : 3, g < 2 ? 48 : 120), values[m]);
                assertEq(VestingMath.monthlyVested(allocations[g], tge, ts + 1, g < 2 ? 12 : 3, g < 2 ? 48 : 120), values[m]);
                if (m > 0) assertEq(VestingMath.monthlyVested(allocations[g], tge, ts - 1, g < 2 ? 12 : 3, g < 2 ? 48 : 120), values[m - 1]);
            }
        }
        uint256[] memory emission = vm.parseJsonUintArray(raw, ".emission");
        assertEq(emission.length, 289);
        for (uint64 m; m < 289; ++m) {
            uint64 ts = tge + m * 30 days;
            assertEq(VestingMath.emissionVested(tge, ts), emission[m]);
            assertEq(VestingMath.emissionVested(tge, ts + 1), emission[m]);
            if (m > 0) assertEq(VestingMath.emissionVested(tge, ts - 1), emission[m - 1]);
        }
    }
}
