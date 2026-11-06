// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {Test} from "forge-std/Test.sol";
import {LIFEVestingVault} from "../src/LIFEVestingVault.sol";
contract SharedFirstTest is Test {
    function test_SharedGrantInterfaceExists() public {
        LIFEVestingVault implementation = new LIFEVestingVault();
        vm.expectRevert();
        implementation.details(bytes32(uint256(1)));
    }
}
