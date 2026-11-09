// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {VestingMath} from "../../src/libraries/VestingMath.sol";

contract ScheduleReferenceTest is Test {
    /// Investors/Advisors (groups 0, 1) use the cliff-unlock schedule; others vest linearly after the cliff.
    function vested(uint256 g, uint256 allocation, uint64 tge, uint64 ts, uint16 cliff, uint16 n) internal pure returns (uint256) {
        return g < 2 ? VestingMath.cliffUnlockVested(allocation, tge, ts, cliff, n) : VestingMath.monthlyVested(allocation, tge, ts, cliff, n);
    }

    function test_AllWorkbookMonthsAndSecondBoundaries() public view {
        string memory raw = vm.readFile("test/reference/schedule.json");
        string[5] memory names = [string("investors"), "advisors", "foundation", "ecosystem", "team"];
        uint256[5] memory allocations = [uint256(2_000_000_000e18), 500_000_000e18, 800_000_000e18, 1_000_000_000e18, 700_000_000e18];
        uint16[5] memory cliffs = [uint16(12), 12, 3, 3, 12];
        uint16[5] memory periods = [uint16(48), 48, 120, 120, 48];
        uint64 tge = 100000;
        for (uint256 g; g < 5; ++g) {
            uint256[] memory values = vm.parseJsonUintArray(raw, string.concat(".", names[g]));
            assertEq(values.length, 289);
            for (uint64 m; m < 289; ++m) {
                uint64 ts = tge + m * 30 days;
                assertEq(vested(g, allocations[g], tge, ts, cliffs[g], periods[g]), values[m]);
                assertEq(vested(g, allocations[g], tge, ts + 1, cliffs[g], periods[g]), values[m]);
                if (m > 0) assertEq(vested(g, allocations[g], tge, ts - 1, cliffs[g], periods[g]), values[m - 1]);
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
