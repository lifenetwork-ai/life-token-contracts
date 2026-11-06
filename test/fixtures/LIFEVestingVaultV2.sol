// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {LIFEVestingVault} from "../../src/LIFEVestingVault.sol";

/// @custom:oz-upgrades-from LIFEVestingVault
/// @custom:oz-upgrades-unsafe-allow missing-initializer
/// @dev Test-only V2 adds a pure function, no state or initialization; inherits locked V1 initializer.
contract LIFEVestingVaultV2 is LIFEVestingVault {
    function version() external pure returns (uint256) {
        return 2;
    }
}
