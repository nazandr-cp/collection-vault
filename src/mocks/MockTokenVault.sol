// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVault} from "../interfaces/IVault.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";

/**
 * @title MockTokenVault
 * @notice A simplified mock implementation of the IVault interface for testing.
 * @dev This mock assumes a fixed yield amount per NFT per collection for simplicity.
 *      It doesn't handle time accrual or complex logic.
 */
contract MockTokenVault is IVault, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable yieldToken;
    uint256 public defaultYieldAmount; // Simple: Fixed yield per NFT

    // Track distributed yield to prevent double claims within the same block/call scope
    // In a real vault, this might be more complex (e.g., based on last claim time)
    mapping(address => mapping(address => uint256)) public claimedYields; // user => collection => amount

    constructor(address _yieldTokenAddress) Ownable(msg.sender) {
        require(_yieldTokenAddress != address(0), "MockTokenVault: Zero address");
        yieldToken = IERC20(_yieldTokenAddress);
    }

    // --- IVault Implementation ---

    function getYieldToken() external view override returns (IERC20) {
        return yieldToken;
    }

    /**
     * @notice Mock calculation: returns a fixed default amount per NFT.
     * @dev Ignores the user and collection address for simplicity in this mock.
     */
    function getPendingYield(address, /* user */ address, /* collectionAddress */ uint256 nftCount)
        public
        view
        override
        returns (uint256 amount)
    {
        // Simple mock logic: total yield = count * fixed amount
        // A real implementation would be much more complex.
        // Prevent underflow if nftCount is 0
        if (nftCount == 0) {
            return 0;
        }
        uint256 totalYield = nftCount * defaultYieldAmount;
        // Consider already claimed amounts if implementing stateful claims in mock
        // uint256 previouslyClaimed = claimedYields[user][collectionAddress];
        // return totalYield > previouslyClaimed ? totalYield - previouslyClaimed : 0;
        return totalYield;
    }

    /**
     * @notice Mock distribution: Transfers the calculated amount if available.
     */
    function distributeYield(address user, uint256 amount) external override returns (bool success) {
        // Basic check: Ensure caller is authorized (e.g., VaultManager)
        // In this mock, we might skip strict auth for easier testing setup
        // require(msg.sender == vaultManagerAddress, "MockTokenVault: Unauthorized caller");

        if (amount == 0) {
            // Optionally revert or just return true if zero amount is okay
            // revert("MockTokenVault: Cannot distribute zero yield");
            return true;
        }

        uint256 availableBalance = yieldToken.balanceOf(address(this));
        if (availableBalance < amount) {
            // Optionally revert or return false
            // revert("MockTokenVault: Insufficient balance");
            return false;
        }

        // Use SafeERC20 transfer
        yieldToken.safeTransfer(user, amount);

        // Update claimed amounts (simple tracking for mock)
        // Note: This simplistic tracking doesn't prevent re-claiming across transactions
        // claimedYields[user][collectionAddress] += amount; // Need collection context here

        return true;
    }

    // --- Mock Configuration ---

    function setDefaultYieldAmount(uint256 _amount) external onlyOwner {
        defaultYieldAmount = _amount;
    }

    /**
     * @notice Helper to fund the mock vault with yield tokens.
     */
    function fundVault(uint256 /* amount */ ) external payable {
        // Allow funding via ETH transfer if yieldToken is WETH, or require direct ERC20 transfer
        // For simplicity, assuming direct ERC20 transfer is handled externally by tests
        require(msg.value == 0, "MockTokenVault: Use direct ERC20 transfer to fund");
        // External funding through yieldToken.transfer(address(this), amount)
    }

    // Helper function for tests to check internal balance
    function getVaultBalance() external view returns (uint256) {
        return yieldToken.balanceOf(address(this));
    }
}
