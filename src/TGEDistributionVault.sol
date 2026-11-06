// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ILaunchReadiness} from "./interfaces/ILaunchReadiness.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TGERegistry} from "./TGERegistry.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TGEDistributionVault is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;
    TGERegistry public immutable registry;
    address public immutable configurator;
    uint256 public constant ALLOCATION = 1_900_000_000e18;
    uint256 public totalAllocated;
    uint256 public totalClaimed;
    bool public isSealed;
    mapping(address => uint256) public allocations;
    mapping(address => bool) public claimed;
    error InvalidConfiguration();
    error Unauthorized();
    error InvalidState();
    event AllocationSet(address indexed recipient, uint256 amount);
    event Sealed();
    event Claimed(address indexed recipient, uint256 amount);

    constructor(IERC20 t, TGERegistry r, address c) {
        if (address(t).code.length == 0 || address(r).code.length == 0 || c == address(0)) revert InvalidConfiguration();
        token = t;
        registry = r;
        configurator = c;
    }

    function setAllocation(address recipient, uint256 amount) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (isSealed || registry.tge() != 0) revert InvalidState();
        if (recipient == address(0) || recipient == address(this) || recipient == address(token) || recipient == address(registry)
            || !ILaunchReadiness(address(registry.readiness())).isRecipientAllowed(recipient)) revert InvalidConfiguration();
        uint256 total = totalAllocated - allocations[recipient] + amount;
        if (total > ALLOCATION) revert InvalidConfiguration();
        totalAllocated = total;
        allocations[recipient] = amount;
        emit AllocationSet(recipient, amount);
    }

    function seal() external {
        if (msg.sender != configurator) revert Unauthorized();
        if (
            isSealed || registry.tge() != 0 || totalAllocated != ALLOCATION
                || token.balanceOf(address(this)) < ALLOCATION
        ) {
            revert InvalidState();
        }
        isSealed = true;
        emit Sealed();
    }

    function claim(address recipient) external nonReentrant returns (uint256 amount) {
        if (!isSealed) revert InvalidState();
        uint64 t = registry.tge();
        if (t == 0 || block.timestamp < t || claimed[recipient]) return 0;
        amount = allocations[recipient];
        if (amount == 0) return 0;
        claimed[recipient] = true;
        totalClaimed += amount;
        token.safeTransfer(recipient, amount);
        emit Claimed(recipient, amount);
    }

    function isReady() external view returns (bool) {
        return isSealed && token.balanceOf(address(this)) + totalClaimed >= ALLOCATION;
    }
}
