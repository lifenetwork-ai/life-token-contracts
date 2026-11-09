// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

library VestingMath {
    uint256 internal constant MONTH = 30 days;

    /// @dev Callers validate schedule and allocation <= 10 billion LIFE at creation.
    function monthlyVested(uint256 allocation, uint64 tge, uint64 timestamp, uint16 cliffMonths, uint16 periods)
        internal
        pure
        returns (uint256)
    {
        if (tge == 0 || timestamp < tge) return 0;
        uint256 m = (timestamp - tge) / MONTH;
        if (m <= cliffMonths) return 0;
        uint256 k = m - cliffMonths;
        if (k >= periods) return allocation;
        return allocation * k / periods;
    }

    /// @dev Cliff-unlock schedule: nothing before the cliff month; at the cliff the elapsed
    ///      share (cliffMonths/periods) unlocks at once, then 1/periods per month until fully
    ///      vested at month `periods`. Investors/Advisors use cliff 12, periods 48: 25% at
    ///      Month 12, then 1/48 per month through Month 48.
    function cliffUnlockVested(uint256 allocation, uint64 start, uint64 timestamp, uint16 cliffMonths, uint16 periods)
        internal
        pure
        returns (uint256)
    {
        if (start == 0 || timestamp < start) return 0;
        uint256 m = (timestamp - start) / MONTH;
        if (m < cliffMonths) return 0;
        if (m >= periods) return allocation;
        return allocation * m / periods;
    }

    function emissionVested(uint64 tge, uint64 timestamp) internal pure returns (uint256 vested) {
        if (tge == 0 || timestamp < tge) return 0;
        uint256 m = (timestamp - tge) / MONTH;
        if (m < 48) return 0;
        uint256 batches = (m - 48) / 3 + 1;
        if (batches >= 80) return 3_100_000_000e18;
        for (uint256 stage; stage < 5; ++stage) {
            uint256 n = batches > 16 ? 16 : batches;
            vested += n * (100_000_000e18 >> stage);
            batches -= n;
        }
    }
}
