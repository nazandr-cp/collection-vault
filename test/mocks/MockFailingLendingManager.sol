// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockFailingLendingManager {
    bool private _shouldFailWithdraw;
    bool private _shouldFailDeposit;
    uint256 private _totalAssets;
    IERC20 private _asset;

    constructor(address asset, uint256 initialTotalAssets) {
        _asset = IERC20(asset);
        _totalAssets = initialTotalAssets;
    }

    function setShouldFailWithdraw(bool shouldFail) external {
        _shouldFailWithdraw = shouldFail;
    }

    function setShouldFailDeposit(bool shouldFail) external {
        _shouldFailDeposit = shouldFail;
    }

    function setTotalAssets(uint256 totalAssets) external {
        _totalAssets = totalAssets;
    }

    function asset() external view returns (IERC20) {
        return _asset;
    }

    function totalAssets() external view returns (uint256) {
        return _totalAssets;
    }

    function depositToLendingProtocol(uint256 amount) external returns (bool) {
        if (_shouldFailDeposit) {
            return false;
        }
        _totalAssets += amount;
        return true;
    }

    function withdrawFromLendingProtocol(uint256 amount) external returns (bool) {
        if (_shouldFailWithdraw) {
            return false;
        }
        if (amount > _totalAssets) {
            return false;
        }
        _totalAssets -= amount;
        return true;
    }

    function totalPrincipalDeposited() external view returns (uint256) {
        return _totalAssets;
    }
}
