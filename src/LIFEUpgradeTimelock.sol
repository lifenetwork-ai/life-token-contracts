// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract LIFEUpgradeTimelock is TimelockController {
    uint256 private effectiveDelay = 48 hours;
    error InvalidDelay();
    error InvalidGovernance();

    constructor(address governance) TimelockController(48 hours, _one(governance), _one(governance), address(0)) {
        if (governance == address(0)) revert InvalidGovernance();
    }

    /// @dev TimelockController uses this virtual getter when scheduling operations.
    function getMinDelay() public view override returns (uint256) {
        return effectiveDelay;
    }

    function updateDelay(uint256 delay) external override {
        if (msg.sender != address(this)) revert TimelockUnauthorizedCaller(msg.sender);
        if (delay < 48 hours) revert InvalidDelay();
        emit MinDelayChange(effectiveDelay, delay);
        effectiveDelay = delay;
    }

    function _one(address a) private pure returns (address[] memory r) {
        r = new address[](1);
        r[0] = a;
    }
}
