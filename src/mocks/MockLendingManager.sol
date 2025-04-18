// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {IERC20} from "@openzeppelin-contracts-5.3.0/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

/**
 * @title MockLendingManager
 * @notice Mock contract for testing ERC4626Vault interactions.
 */
contract MockLendingManager is ILendingManager {
    IERC20 private immutable _asset;
    address public rewardsControllerAddress; // Address of the authorized RewardsController

    /**
     * @notice Get the underlying ERC20 asset managed by the lending manager.
     * @return ERC20 asset address.
     */
    function asset() external view override returns (IERC20) {
        return _asset;
    }

    uint256 internal mockBaseRewardPerBlock;
    uint256 internal mockTotalAssets;
    bool internal shouldTransferYieldRevert;
    bool public depositResult = true;
    bool public withdrawResult = true;
    bool public transferYieldResult = true;

    // Track calls
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
        _asset = IERC20(_assetAddress);
    }

    // --- Mock Control Functions ---
    function setRewardsController(address _controller) external {
        // In a real scenario, this would likely be restricted (e.g., Ownable)
        rewardsControllerAddress = _controller;
    }

    function setDepositResult(bool _result) external {
        depositResult = _result;
    }

    function setWithdrawResult(bool _result) external {
        withdrawResult = _result;
    }

    function setMockBaseRewardPerBlock(uint256 _reward) external {
        mockBaseRewardPerBlock = _reward;
    }

    function setMockTotalAssets(uint256 _assets) external {
        mockTotalAssets = _assets;
    }

    function setShouldTransferYieldRevert(bool _revert) external {
        shouldTransferYieldRevert = _revert;
    }

    function setExpectedTransferYield(uint256 _amount, address _recipient, bool _result) external {
        expectedTransferAmount = _amount;
        expectedTransferRecipient = _recipient;
        transferYieldResult = _result;
        transferYieldExpectationSet = true;
    }

    // --- ILendingManager Implementation ---
    // Corrected signature to match ILendingManager interface
    function depositToLendingProtocol(uint256 amount) external override returns (bool success) {
        depositCalledCount++;
        emit MockDepositCalled(amount);
        success = depositResult;
        if (success && amount > 0) {
            // Simulate LM pulling assets from the Vault (msg.sender)
            // Requires Vault to have approved the LM
            _asset.transferFrom(msg.sender, address(this), amount);
        }
        return success;
    }

    function withdrawFromLendingProtocol(uint256 amount) external override returns (bool success) {
        withdrawCalledCount++;
        emit MockWithdrawCalled(amount);
        success = withdrawResult;
        if (success) {
            // Check actual balance before transfer
            if (_asset.balanceOf(address(this)) >= amount) {
                // Simulate asset transfer FROM mock TO vault
                _asset.transfer(msg.sender, amount);
            } else {
                // If mock doesn't have the funds, withdraw fails
                success = false;
            }
        }
        return success;
    }

    function totalAssets() external view override returns (uint256) {
        // Return mock value if set, otherwise fallback (e.g., balance)
        return mockTotalAssets > 0 ? mockTotalAssets : _asset.balanceOf(address(this));
    }

    function getBaseRewardPerBlock() external view override returns (uint256) {
        // Return mock value
        return mockBaseRewardPerBlock;
    }

    function transferYield(uint256 amount, address recipient) external override returns (bool success) {
        transferYieldCalledCount++;
        emit MockTransferYieldCalled(amount, recipient);

        // Check if the caller is the authorized RewardsController
        require(msg.sender == rewardsControllerAddress, "MockLM: Caller is not the RewardsController");

        if (shouldTransferYieldRevert) {
            revert("MockLM: transferYield forced revert");
        }

        // Check specific expectations if set
        if (transferYieldExpectationSet) {
            require(amount == expectedTransferAmount, "MockLM: Transfer amount mismatch");
            require(recipient == expectedTransferRecipient, "MockLM: Transfer recipient mismatch");
            success = transferYieldResult;
            transferYieldExpectationSet = false; // Reset expectation
        } else {
            // Default behavior if no specific expectation is set
            success = true;
        }

        // Simulate transfer if successful so far
        if (success) {
            uint256 currentBalance = _asset.balanceOf(address(this));
            console.log("MockLM.transferYield: Attempting transfer...");
            console.log("  - Sender (MockLM):", address(this));
            console.log("  - Recipient:", recipient);
            console.log("  - Amount:", amount);
            console.log("  - Sender Balance:", currentBalance);

            if (currentBalance >= amount) {
                // Balance check
                _asset.transfer(recipient, amount); // <<< THE TRANSFER
            } else {
                // Fail if mock doesn't have enough funds, even if expectation was true
                success = false;
            }
        }
        return success;
    }

    // asset() is explicitly implemented above
}
