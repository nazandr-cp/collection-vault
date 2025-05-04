// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

/**
 * @title MockLendingManager
 * @notice Mock contract for testing ERC4626Vault interactions.
 */
contract MockLendingManager is ILendingManager {
    IERC20 private immutable _asset;
    address public rewardsControllerAddress; // Address of the authorized RewardsController
    address public mockCTokenAddress; // <-- Add mock cToken address

    uint256 private _mockAvailableYield = type(uint256).max; // Default to max, effectively no cap

    /**
     * @notice Get the underlying ERC20 asset managed by the lending manager.
     * @return ERC20 asset address.
     */
    function asset() external view override returns (IERC20) {
        return _asset;
    }

    /**
     * @notice Get the mock cToken address.
     * @return Mock cToken address.
     */
    function cToken() external view override returns (address) {
        // <-- Implement interface function
        return mockCTokenAddress;
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
    // Remove expectedTransferAmount, transferYieldExpectationSet
    address public expectedTransferRecipient; // Keep recipient check if needed, or remove if not used
    bool private recipientExpectationSet = false; // Flag for recipient check

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

    function setMockCTokenAddress(address _cToken) external {
        // <-- Add setter for mock cToken
        mockCTokenAddress = _cToken;
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

    // Remove setExpectedTransferYield

    function setMockAvailableYield(uint256 _yield) external {
        _mockAvailableYield = _yield;
    }

    // Optional: Keep a way to set expected recipient if needed for specific tests
    function setExpectedRecipient(address _recipient) external {
        expectedTransferRecipient = _recipient;
        recipientExpectationSet = true;
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

    // --- Added to satisfy ILendingManager interface ---
    function totalPrincipalDeposited() external view override returns (uint256) {
        return 0; // Simple mock implementation, returns 0
    }
    // --- End Added ---

    function getBaseRewardPerBlock() external view override returns (uint256) {
        // Return mock value
        return mockBaseRewardPerBlock;
    }

    // --- Added to satisfy ILendingManager interface ---
    function getAvailableYield() external view returns (uint256) {
        // Removed override
        return _mockAvailableYield;
    }
    // --- End Added ---

    function transferYield(uint256 amount, address recipient) external override returns (uint256 amountTransferred) {
        transferYieldCalledCount++;
        emit MockTransferYieldCalled(amount, recipient);

        // Check if the caller is the authorized RewardsController
        require(msg.sender == rewardsControllerAddress, "MockLM: Caller is not the RewardsController");

        // Check recipient if expectation was set
        if (recipientExpectationSet) {
            require(recipient == expectedTransferRecipient, "MockLM: Transfer recipient mismatch");
            recipientExpectationSet = false; // Reset expectation
        }

        if (shouldTransferYieldRevert) {
            revert("MockLM: transferYield forced revert");
        }

        // Determine actual amount to transfer based on mock available yield and requested amount
        uint256 available = this.getAvailableYield(); // Call external function using 'this'
        amountTransferred = amount > available ? available : amount;

        // Simulate transfer if amount > 0 and mock is set to succeed
        if (amountTransferred > 0 && transferYieldResult) {
            uint256 currentBalance = _asset.balanceOf(address(this));
            console.log("MockLM.transferYield: Attempting transfer...");
            console.log("  - Sender (MockLM):", address(this));
            console.log("  - Recipient:", recipient);
            console.log("  - Requested Amount:", amount);
            console.log("  - Available Yield:", available);
            console.log("  - Amount To Transfer:", amountTransferred);
            console.log("  - Sender Balance:", currentBalance);

            if (currentBalance >= amountTransferred) {
                _asset.transfer(recipient, amountTransferred);
            } else {
                console.log("MockLM.transferYield: Insufficient balance for transfer.");
                amountTransferred = 0; // Simulate failure due to insufficient funds
            }
        } else if (!transferYieldResult) {
            console.log("MockLM.transferYield: Mock set to fail transfer.");
            amountTransferred = 0; // Simulate failure based on flag
        } else {
            console.log("MockLM.transferYield: Calculated transfer amount is zero.");
            amountTransferred = 0; // No transfer needed
        }

        return amountTransferred;
    }

    // --- Mock Implementation for redeemAllCTokens ---
    function redeemAllCTokens(address recipient) external override returns (uint256 amountRedeemed) {
        // Simple mock: Assume it redeems some fixed amount or an amount based on a mock state.
        // For now, just return 0 and transfer nothing.
        // A more complex mock could track cToken balances and simulate redemption.
        amountRedeemed = 0; // Placeholder
        // if (amountRedeemed > 0) {
        //     mockAsset.transfer(recipient, amountRedeemed);
        // }
        return amountRedeemed;
    }
}
