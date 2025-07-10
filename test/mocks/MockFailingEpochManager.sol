// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockFailingEpochManager {
    bool private _shouldFailAllocateVaultYield;
    bool private _shouldFailGetCurrentEpochId;
    uint256 private _currentEpochId;

    constructor(uint256 initialEpochId) {
        _currentEpochId = initialEpochId;
    }

    function setShouldFailAllocateVaultYield(bool shouldFail) external {
        _shouldFailAllocateVaultYield = shouldFail;
    }

    function setShouldFailGetCurrentEpochId(bool shouldFail) external {
        _shouldFailGetCurrentEpochId = shouldFail;
    }

    function setCurrentEpochId(uint256 epochId) external {
        _currentEpochId = epochId;
    }

    function getCurrentEpochId() external view returns (uint256) {
        if (_shouldFailGetCurrentEpochId) {
            revert("MockFailingEpochManager: getCurrentEpochId failed");
        }
        return _currentEpochId;
    }

    function allocateVaultYield(address, uint256) external {
        if (_shouldFailAllocateVaultYield) {
            revert("MockFailingEpochManager: allocateVaultYield failed");
        }
    }
}
