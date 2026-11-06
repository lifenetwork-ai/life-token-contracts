// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
/// @custom:oz-upgrades-from LIFEVestingVault
/// @dev Deliberately invalid test fixture: replaces the deployed namespace with incompatible fields.
contract IncompatibleVesting is UUPSUpgradeable {
    /// @custom:storage-location erc7201:life.storage.SharedVesting
    struct VaultStorage { uint256 token; address allocation; }
    function initialize() external initializer {__UUPSUpgradeable_init();}
    function _authorizeUpgrade(address) internal pure override {revert();}
}
