// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ISubsidyDistributor
 * @dev Interface for the SubsidyDistributor contract, which manages yield buffering,
 * EMA calculations, and index distribution for user rewards.
 */
interface ISubsidyDistributor {
    /**
     * @dev Emitted when yield buffer is received from the MarketVault.
     * @param fromMarketVault The address of the MarketVault contract.
     * @param amount The amount of yield received.
     */
    event BufferReceived(address indexed fromMarketVault, uint256 amount);

    /**
     * @dev Emitted when the Exponential Moving Average (EMA) is calculated.
     * @param newEMA The newly calculated EMA value.
     * @param blockNumber The block number at which the EMA was calculated.
     */
    event EMACalculated(uint120 newEMA, uint40 blockNumber);

    /**
     * @dev Emitted when the global market index is pushed (updated).
     * @param newIndex The new global market index (index64x64).
     * @param deltaIndex The change in the index (dIdx).
     * @param yieldProcessed The amount of yield processed to update the index.
     */
    event IndexPushed(uint128 newIndex, uint128 deltaIndex, uint256 yieldProcessed);

    /**
     * @dev Emitted when a user's rewards are accrued.
     * @param user The address of the user.
     * @param weight The new weight of the user.
     * @param accruedAmount The amount of rewards accrued in this transaction.
     */
    event UserAccrued(address indexed user, uint32 weight, uint128 accruedAmount);

    /**
     * @dev Emitted when a user claims their rewards.
     * @param user The address of the user.
     * @param claimedAmount The amount of rewards claimed.
     */
    event RewardsClaimed(address indexed user, uint256 claimedAmount);

    /**
     * @dev Represents a user's state in the subsidy distribution system.
     * @param accrued The total rewards accrued by the user but not yet claimed.
     * @param index64x64 The user's personal market index at their last interaction.
     * @param weight The user's weight in the reward distribution.
     * @param snapshotId The ID of the RootGuardian snapshot active at the user's last interaction.
     * @param reserved Reserved for future use.
     */
    struct User {
        uint128 accrued;
        uint64 index64x64;
        uint32 weight;
        uint32 snapshotId;
        uint64 reserved;
    }

    /**
     * @notice Receives yield from the MarketVault and adds it to the internal buffer.
     * @dev Only callable by the authorized MarketVault contract.
     * @param amount The amount of yield to add to the buffer.
     */
    function takeBuffer(uint256 amount) external;

    /**
     * @notice Calculates the Exponential Moving Average (EMA) of the yield buffer.
     * @dev May be rate-limited.
     */
    function lazyEMA() external; // Or internal, triggered by other actions

    /**
     * @notice Updates the global market index based on accumulated yield and EMA.
     * @dev Protected by deltaIdxMax to prevent excessive index changes.
     * Potentially triggered by a BountyKeeper.
     */
    function pushIndex() external;

    /**
     * @notice Accrues rewards for a user based on their weight and the current market index.
     * @dev Updates the user's personal index and accrued rewards.
     * @param user The address of the user.
     * @param weight The new weight for the user.
     */
    function accrueUser(address user, uint256 weight) external;

    /**
     * @notice Allows a user to claim their accrued rewards.
     * @dev Transfers the accrued rewards to the user.
     * @param user The address of the user claiming rewards.
     * @return claimedAmount The amount of rewards claimed.
     */
    function claimRewards(address user) external returns (uint256 claimedAmount);

    /**
     * @notice View function to get the current amount in the yield buffer.
     * @return bufferAmount The current yield buffer amount.
     */
    function getBufferAmount() external view returns (uint256 bufferAmount);

    /**
     * @notice View function to get the timestamp of the last index push.
     * @return lastPushTimestamp The timestamp of the last call to pushIndex.
     */
    function getLastPushTimestamp() external view returns (uint256 lastPushTimestamp);

    /**
     * @notice View function to get user data.
     * @param userAddress The address of the user.
     * @return userData The User struct for the specified address.
     */
    function users(address userAddress) external view returns (User memory userData);

    /**
     * @notice View function to get the global market index.
     * @return globalIndex The current global market index (index64x64).
     */
    function globalIndex() external view returns (uint128 globalIndex);

    /**
     * @notice View function to get the total borrow EMA.
     * @return totalBorrowEMA_ The current total borrow EMA.
     */
    function totalBorrowEMA() external view returns (uint120 totalBorrowEMA_);

    /**
     * @notice View function to get the last block number used for EMA calculation.
     * @return lastBlock_ The last block number.
     */
    function lastBlock() external view returns (uint40 lastBlock_);

    /**
     * @notice View function to get the maximum allowed change in index per push.
     * @return deltaIdxMax_ The deltaIdxMax value.
     */
    function deltaIdxMax() external view returns (uint256 deltaIdxMax_);
}
