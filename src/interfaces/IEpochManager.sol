// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IEpochManager {
    function getCurrentEpochId() external view returns (uint256);
    function allocateVaultYield(address vault, uint256 amount) external;
}
