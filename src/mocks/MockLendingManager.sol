// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";

/**
 * @title MockLendingManager
 * @notice Mock contract for testing ERC4626Vault interactions.
 */
contract MockLendingManager is ILendingManager {
    IERC20 public immutable asset;
    uint256 public currentTotalAssets;
    bool public depositResult = true; // Default success
    bool public withdrawResult = true; // Default success
    bool public transferYieldResult = true; // Default success

    // Track calls (optional, could use forge cheats)
    uint256 public depositCalledCount;
    uint256 public withdrawCalledCount;
    uint256 public transferYieldCalledCount;
    uint256 public expectedTransferAmount;
    address public expectedTransferRecipient;
    bool private transferYieldExpectationSet = false;

    event MockDepositCalled(uint256 amount);
    event MockWithdrawCalled(uint256 amount);
    event MockTransferYieldCalled(uint256 amount, address recipient);

    constructor(address _assetAddress) {
        asset = IERC20(_assetAddress);
    }

    // --- Mock Control Functions ---
    function setTotalAssets(uint256 _totalAssets) external {
        currentTotalAssets = _totalAssets;
    }

    function setExpectedDepositResult(bool _result) external {
        depositResult = _result;
    }

    function setExpectedWithdrawResult(bool _result) external {
        withdrawResult = _result;
    }

    function setExpectedTransferYieldResult(bool _result) external {
        transferYieldResult = _result;
    }

    function setExpectedTransferYield(uint256 _amount, address _recipient, bool _result) external {
        expectedTransferAmount = _amount;
        expectedTransferRecipient = _recipient;
        transferYieldResult = _result; // Store the expected result
        transferYieldExpectationSet = true;
    }

    // --- ILendingManager Implementation ---
    function depositToLendingProtocol(uint256 amount) external override returns (bool success) {
        depositCalledCount++;
        emit MockDepositCalled(amount);
        success = depositResult;
        if (success) {
            // Vault now PUSHES assets via transfer before calling this.
            // Mock just needs to update its internal asset count.
            // Remove the transferFrom call.
            // asset.transferFrom(msg.sender, address(this), amount);
            currentTotalAssets += amount; // Update internal state on success
        }
        return success;
    }

    function withdrawFromLendingProtocol(uint256 amount) external override returns (bool success) {
        withdrawCalledCount++;
        emit MockWithdrawCalled(amount);
        success = withdrawResult;
        if (success) {
            // Prevent underflow if mock is somehow asked to withdraw more than it has
            if (currentTotalAssets >= amount) {
                // Simulate asset transfer FROM mock (address(this)) TO vault (msg.sender)
                // Requires mock to hold sufficient assets.
                // Check balance before transfer (basic check)
                if (asset.balanceOf(address(this)) >= amount) {
                    asset.transfer(msg.sender, amount);
                    currentTotalAssets -= amount;
                } else {
                    // If mock doesn't have the funds, withdraw fails regardless of withdrawResult flag
                    success = false;
                }
            } else {
                success = false; // Cannot withdraw more than total assets
                currentTotalAssets = 0; // Should not happen if checks are correct before calling
            }
        }
        return success;
    }

    function totalAssets() external view override returns (uint256) {
        return currentTotalAssets;
    }

    function getBaseRewardPerBlock() external pure override returns (uint256) {
        // Return a fixed value or make configurable for testing RewardsController
        return 0.001 ether; // Example fixed value
    }

    function transferYield(uint256 amount, address recipient) external override returns (bool success) {
        transferYieldCalledCount++;
        emit MockTransferYieldCalled(amount, recipient);

        // If expectation was set, validate and use stored result
        if (transferYieldExpectationSet) {
            require(amount == expectedTransferAmount, "MockLM: Transfer amount mismatch");
            require(recipient == expectedTransferRecipient, "MockLM: Transfer recipient mismatch");
            success = transferYieldResult;
            transferYieldExpectationSet = false; // Reset expectation
        } else {
            // Default behavior if no expectation was set
            success = true; // Or use the last set transferYieldResult
        }

        // Simulate asset transfer only on success
        if (success) {
            // Check balance before transfer
            if (asset.balanceOf(address(this)) >= amount) {
                asset.transfer(recipient, amount);
            } else {
                success = false; // Fail if mock doesn't have enough funds
            }
        }
        return success;
    }

    // asset() is implicitly implemented via the public state variable
}
