// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface ILaunchReadiness {
    function isRecipientAllowed(address recipient) external view returns (bool);
    function isReady() external view returns (bool);
}
