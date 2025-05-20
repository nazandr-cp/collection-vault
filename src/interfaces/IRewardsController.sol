// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICollectionsVault} from "./ICollectionsVault.sol";

interface IRewardsController {
    enum RewardBasis {
        DEPOSIT,
        BORROW
    }

    enum WeightFunctionType {
        LINEAR,
        EXPONENTIAL
    }

    struct WeightFunction {
        WeightFunctionType fnType;
        int256 p1;
        int256 p2;
    }

    struct Claim {
        address account;
        address collection;
        uint256 secondsUser;
        uint256 nonce;
        uint256 deadline;
    }

    //   ========== Events ==========
    event RewardsClaimedForLazy(
        address indexed account,
        address indexed collection,
        uint256 dueAmount,
        uint256 nonce,
        uint256 secondsUser,
        uint256 secondsColl,
        uint256 incRPS,
        uint256 yieldSlice
    );
    event NewCollectionWhitelisted(address indexed collection, RewardBasis rewardBasis, uint256 sharePercentage);
    event WhitelistCollectionRemoved(address indexed collection);
    event CollectionRewardShareUpdated(
        address indexed collection, uint256 oldSharePercentage, uint256 newSharePercentage
    );
    event TrustedSignerUpdated(address oldSigner, address newSigner, address indexed changedBy);
    event BatchRewardsClaimedForLazy(address indexed caller, uint256 totalDue, uint256 numClaims);
    event WeightFunctionSet(address indexed collection, WeightFunction fn);

    //  ====== Errors ======
    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error ClaimExpired();
    error InvalidSecondsColl();
    error InvalidYieldSlice();
    error InsufficientYield();
    error ArrayLengthMismatch();
    error InvalidNonce(uint256 providedNonce, uint256 expectedNonce);
    error VaultMismatch();
    error InvalidRewardSharePercentage(uint16 percentage);

    // ====== Collection Management Functions ======
    function whitelistCollection(address collectionAddress, RewardBasis rewardBasis, uint256 sharePercentage)
        external;
    function removeCollection(address collectionAddress) external;
    function updateCollectionPercentageShare(address collectionAddress, uint256 sharePercentage) external;
    function setWeightFunction(address collectionAddress, WeightFunction calldata fn) external;

    // ====== View Functions ======
    function oracle() external view returns (address);
    function vault() external view returns (ICollectionsVault);

    function lastAssets() external view returns (uint256);
    function yieldLeft() external view returns (uint128);

    function coll(address collectionAddress) external view returns (uint128 accRPS, uint128 lastSeconds);

    function userNonce(address userAddress) external view returns (uint128 nonce);
    function userSecondsPaid(address userAddress, address collectionAddress)
        external
        view
        returns (uint128 secondsPaid);

    // ====== User/Claim Functions ======
    function previewClaim(Claim[] calldata claims) external view returns (uint256 totalDue);
    function claimLazy(Claim[] calldata claims, bytes[] calldata signatures) external;

    // ====== Admin Functions ======
    function updateTrustedSigner(address newSigner) external;

    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
