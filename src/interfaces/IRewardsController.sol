// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ICollectionsVault} from "./ICollectionsVault.sol";

interface IRewardsController {
    enum CollectionType {
        ERC721,
        ERC1155
    }

    enum RewardBasis {
        DEPOSIT,
        BORROW,
        FIXED_POOL
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
    event NewCollectionWhitelisted(
        address indexed collection, CollectionType collectionType, RewardBasis rewardBasis, uint16 sharePercentage
    );
    event WhitelistCollectionRemoved(address indexed collection);
    event CollectionRewardShareUpdated(
        address indexed collection, uint16 oldSharePercentage, uint16 newSharePercentage
    );
    event TrustedSignerUpdated(address oldSigner, address newSigner, address indexed changedBy);
    event BatchRewardsClaimedForLazy(address indexed caller, uint256 totalDue, uint256 numClaims);
    event WeightFunctionSet(address indexed collection, WeightFunction fn);
    event RewardClaimed(address vault, address indexed user, uint256 amount);
    event RewardPerBlockUpdated(address indexed vault, uint128 rewardPerBlock);
    event VaultUpdated(address indexed newVaultAddress);

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
    error InvalidCollectionInterface(address collection, bytes4 interfaceId);
    error CannotSetSignerToZeroAddress();

    // ====== Collection Management Functions ======
    function whitelistCollection(
        address collectionAddress,
        CollectionType collectionType,
        RewardBasis rewardBasis,
        uint16 sharePercentageBps
    ) external;
    function removeCollection(address collectionAddress) external;
    function updateCollectionPercentageShare(address collectionAddress, uint16 newSharePercentageBps) external;

    function setWeightFunction(address collectionAddress, WeightFunction calldata fn) external;

    // ====== View Functions ======
    function oracle() external view returns (address);
    function vault() external view returns (ICollectionsVault);

    function userNonce(address vaultAddress, address userAddress) external view returns (uint64 nonce);
    function userSecondsPaid(address vaultAddress, address userAddress) external view returns (uint64 secondsPaid);

    function vaults(address vaultAddress) external view returns (VaultInfo memory);
    function acc(address vaultAddress, address userAddress) external view returns (AccountInfo memory);

    function collectionRewardBasis(address collectionAddress) external view returns (RewardBasis);

    function isCollectionWhitelisted(address collectionAddress) external view returns (bool);

    // ====== User/Claim Functions ======
    function claimLazy(Claim[] calldata claims, bytes calldata signature) external;
    function syncAccount(address user, address collectionAddress) external;

    // ====== Admin Functions ======
    function updateTrustedSigner(address newSigner) external;

    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);

    // ====== Admin/Keeper Functions ======
    function refreshRewardPerBlock(address vault) external;
    function claimSigner() external view returns (address);
}
