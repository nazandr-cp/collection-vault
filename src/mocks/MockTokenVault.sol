// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockTokenVault
 * @notice A simplified mock implementation of IERC4626VaultMinimal for testing RewardsController.
 * @dev Implements minimal functions needed by RewardsController.
 */
abstract contract MockTokenVault is IERC4626, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable underlyingAsset;
    uint256 public defaultYieldAmount;

    // Mock the deposits mapping needed by RewardsController
    mapping(address => mapping(address => uint256)) public deposits;

    // Track distributed yield
    mapping(address => mapping(address => uint256)) public claimedYields;

    constructor(address _assetAddress) Ownable(msg.sender) {
        require(_assetAddress != address(0), "MockTokenVault: Zero address");
        underlyingAsset = IERC20(_assetAddress);
    }

    // --- IERC4626VaultMinimal Implementation ---

    function asset() external view override returns (address) {
        return address(underlyingAsset);
    }

    // --- Mock Configuration ---

    function setDeposit(address user, address collection, uint256 amount) external onlyOwner {
        deposits[user][collection] = amount;
    }

    function setDefaultYieldAmount(uint256 _amount) external onlyOwner {
        defaultYieldAmount = _amount;
    }

    /**
     * @notice Helper to fund the mock vault with tokens.
     */
    function fundVault(uint256 /* amount */ ) external payable {
        require(msg.value == 0, "MockTokenVault: Use direct ERC20 transfer to fund");
        // External funding through underlyingAsset.transfer(address(this), amount)
    }

    // Helper function for tests to check internal balance
    function getVaultBalance() external view returns (uint256) {
        return underlyingAsset.balanceOf(address(this));
    }
}
