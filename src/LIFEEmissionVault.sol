// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {ILaunchReadiness} from "./interfaces/ILaunchReadiness.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TGERegistry} from "./TGERegistry.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VestingMath} from "./libraries/VestingMath.sol";

contract LIFEEmissionVault is ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public immutable token;
    TGERegistry public immutable registry;
    uint256 public constant ALLOCATION = 3_100_000_000e18;
    address public recipient;
    address public pendingRecipient;
    uint256 public released;
    error InvalidConfiguration();
    error Unauthorized();
    event Released(address indexed recipient, uint256 amount);
    event RecipientProposed(address indexed current, address indexed proposed);
    event RecipientChanged(address indexed previous, address indexed current);

    constructor(IERC20 token_, TGERegistry registry_, address recipient_) {
        if (
            address(token_).code.length == 0 || address(registry_).code.length == 0 || recipient_ == address(0)
                || recipient_ == address(this) || recipient_ == address(token_) || recipient_ == address(registry_)
        ) revert InvalidConfiguration();
        token = token_;
        registry = registry_;
        recipient = recipient_;
    }

    function release() external nonReentrant returns (uint256 amount) {
        amount = releasable();
        if (amount == 0) return 0;
        released += amount;
        token.safeTransfer(recipient, amount);
        emit Released(recipient, amount);
    }

    function releasable() public view returns (uint256) {
        return VestingMath.emissionVested(registry.tge(), uint64(block.timestamp)) - released;
    }

    function isReady() external view returns (bool) {
        return token.balanceOf(address(this)) + released >= ALLOCATION;
    }

    function proposeRecipient(address next) external {
        if (msg.sender != recipient) revert Unauthorized();
        if (next == address(0) || next == address(this) || next == recipient || next == address(token) || next == address(registry)
            || !ILaunchReadiness(address(registry.readiness())).isRecipientAllowed(next)) revert InvalidConfiguration();
        pendingRecipient = next;
        emit RecipientProposed(recipient, next);
    }

    function acceptRecipient() external {
        if (msg.sender != pendingRecipient) revert Unauthorized();
        address old = recipient;
        recipient = msg.sender;
        pendingRecipient = address(0);
        emit RecipientChanged(old, msg.sender);
    }
}
