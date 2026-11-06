// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice LIFE home-chain asset. No privileged functions or upgrades.
contract LIFEToken is ERC20 {
    constructor(address initialRecipient) ERC20("LIFE AI", "LIFE") {
        _mint(initialRecipient, 10_000_000_000e18);
    }
}
