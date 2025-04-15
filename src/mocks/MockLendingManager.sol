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
        asset = IERC20(_assetAddress);
    }

    // --- Mock Control Functions ---
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
    function depositToLendingProtocol(uint256 amount, address /* nftCollection */ )
        external
        override
        returns (bool success)
    {
        depositCalledCount++;
        emit MockDepositCalled(amount);
        success = depositResult;
        // Vault PUSHES assets via transfer before calling this.
        // No need to mock transferFrom here.
        return success;
    }

    function withdrawFromLendingProtocol(uint256 amount) external override returns (bool success) {
        withdrawCalledCount++;
        emit MockWithdrawCalled(amount);
        success = withdrawResult;
        if (success) {
            // Check actual balance before transfer
            if (asset.balanceOf(address(this)) >= amount) {
                // Simulate asset transfer FROM mock TO vault
                asset.transfer(msg.sender, amount);
            } else {
                // If mock doesn't have the funds, withdraw fails
                success = false;
            }
        }
        return success;
    }

    function totalAssets() external view override returns (uint256) {
        // Return mock value if set, otherwise fallback (e.g., balance)
        return mockTotalAssets > 0 ? mockTotalAssets : asset.balanceOf(address(this));
    }

    function getBaseRewardPerBlock() external view override returns (uint256) {
        // Return mock value
        return mockBaseRewardPerBlock;
    }

    function transferYield(uint256 amount, address recipient) external override returns (bool success) {
        transferYieldCalledCount++;
        emit MockTransferYieldCalled(amount, recipient);

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
            if (asset.balanceOf(address(this)) >= amount) {
                asset.transfer(recipient, amount);
            } else {
                // Fail if mock doesn't have enough funds, even if expectation was true
                success = false;
            }
        }
        return success;
    }

    // asset() is implicitly implemented via the public state variable
}
