// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";

/**
 * @title IVault
 * @notice Interface for a token vault that manages yield distribution.
 */
interface IVault {
    /**
     * @notice Returns the ERC20 token distributed by this vault.
     * @return The address of the yield token contract.
     */
    function getYieldToken() external view returns (IERC20);

    /**
     * @notice Calculates the pending yield for a specific user based on their
     *         holdings in a particular NFT collection.
     * @dev The implementation should consider factors like the number of NFTs held,
     *      time accrued, borrow multipliers, etc., as relevant to the specific vault.
     * @param user The address of the user.
     * @param collectionAddress The address of the NFT collection.
     * @param nftCount The number of NFTs the user holds in the specified collection.
     * @return amount The amount of yield token claimable by the user from this vault
     *         for the given collection.
     */
    function getPendingYield(address user, address collectionAddress, uint256 nftCount)
        external
        view
        returns (uint256 amount);

    /**
     * @notice Distributes a specific amount of yield tokens to a user.
     * @dev This function should be callable by the VaultManager to execute the claim.
     *      It must transfer the yield tokens from the vault to the user.
     * @param user The address of the recipient.
     * @param amount The amount of yield tokens to distribute.
     * @return success Boolean indicating if the distribution was successful.
     */
    function distributeYield(address user, uint256 amount) external returns (bool success);

    // --- Optional: Events (Vaults might emit their own distribution events if needed) ---
    // event YieldDistributed(address indexed user, uint256 amount, uint256 timestamp);
}
