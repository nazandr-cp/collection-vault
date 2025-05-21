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
        uint256 secondsColl;
        uint256 incRPS;
        uint256 yieldSlice;
        uint256 nonce;
        uint256 deadline;
    }

    struct VaultInfo {
        uint128 rewardPerBlock; // R_block — подтягиваем из рынка
        uint128 globalRPW; // ∑ R_block / W_tot
        uint128 totalWeight; // Σ W_u (18 dec)      — Δ только при claim!
        uint32 lastUpdateBlock;
        // параметры NFT-модификатора
        uint64 linK; // k  (1e18)  g(N)=1+k·N
        uint64 expR; // r  (1e18)  g(N)=(1+r)^N
        bool useExp;
        // ссылки на market & collection
        address cToken; // чтобы дергать borrowBalanceCurrent/ balanceOfUnderlying
        address nft; // ERC721/1155 c balanceOf()
        bool weightByBorrow; // true=используем borrow, false=deposit
    }

    struct AccountInfo {
        uint128 weight; // W_u на момент последнего claim
        uint128 rewardDebt; // W_u * I  (индекс в тот момент)
        uint128 accrued; // награды, накопленные до последнего claim
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
    event RewardClaimed(address vault, address indexed user, uint256 amount);
    event RewardPerBlockUpdated(address indexed vault, uint128 rewardPerBlock);

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
    function vault() external view returns (address);
    function vaultInfo() external view returns (VaultInfo memory);

    function lastAssets() external view returns (uint256);
    function yieldLeft() external view returns (uint128);

    function coll(address collectionAddress) external view returns (uint128 accRPS, uint128 lastSeconds);

    function userNonce(address userAddress) external view returns (uint128 nonce);
    function userSecondsPaid(address userAddress, address collectionAddress)
        external
        view
        returns (uint128 secondsPaid);

    function vaults(address vaultAddress) external view returns (VaultInfo memory);
    function acc(address vaultAddress, address userAddress) external view returns (AccountInfo memory);

    // ====== User/Claim Functions ======
    function previewClaim(Claim[] calldata claims) external view returns (uint256 totalDue);
    function claimLazy(Claim[] calldata claims, bytes[] calldata signatures) external;
    function claim(address vault, address to) external;

    // ====== Admin Functions ======
    function updateTrustedSigner(address newSigner) external;

    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);

    // ====== Admin/Keeper Functions ======
    function refreshRewardPerBlock(address vault) external;
}
