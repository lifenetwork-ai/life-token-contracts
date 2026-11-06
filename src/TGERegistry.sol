// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ILaunchReadiness} from "./interfaces/ILaunchReadiness.sol";

contract TGERegistry is Ownable2Step {
    uint64 public tge;
    ILaunchReadiness public immutable readiness;
    error InvalidConfiguration();
    error LaunchNotReady();
    error InvalidTGE();
    event TGESet(uint64 timestamp);

    constructor(address governance, address readiness_) Ownable(governance) {
        if (readiness_.code.length == 0) revert InvalidConfiguration();
        readiness = ILaunchReadiness(readiness_);
    }

    function setTGE(uint64 timestamp) external onlyOwner {
        if (tge != 0 || timestamp == 0 || timestamp < block.timestamp) revert InvalidTGE();
        if (!readiness.isReady()) revert LaunchNotReady();
        tge = timestamp;
        emit TGESet(timestamp);
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        if (newOwner == address(0)) revert InvalidConfiguration();
        super.transferOwnership(newOwner);
    }

    function renounceOwnership() public pure override {
        revert InvalidConfiguration();
    }
}
