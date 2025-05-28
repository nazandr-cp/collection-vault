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
        address account; // кому платить
        address collection; // адрес коллекции
        address vault; // адрес vault, в котором хранится yield
        uint256 secondsUser; // (вес × время) списываемые в этом claim
        uint256 amount; // токены к переводу — уже посчитаны off-chain
        uint256 nonce; // защита от повторного применения подписи
        uint256 deadline; // до какого блока/времени подпись действительна
    }

    struct VaultInfo {
        uint32 lastUpdateBlock;
        address cToken;
    }

    struct AccountInfo {
        address vaultAddress;
        uint128 secondsClaimed;
    }

    event NewCollectionWhitelisted(
        address indexed vaultAddress,
        address indexed collectionAddress,
        CollectionType collectionType,
        RewardBasis rewardBasis,
        uint16 sharePercentage,
        WeightFunction weightFunction
    );
    event WhitelistCollectionRemoved(address indexed vaultAddress, address indexed collectionAddress);
    event CollectionRewardShareUpdated(
        address indexed vaultAddress,
        address indexed collectionAddress,
        uint16 oldSharePercentage,
        uint16 newSharePercentage
    );
    event TrustedSignerUpdated(address oldSigner, address newSigner, address indexed changedBy);
    event WeightFunctionSet(address indexed vaultAddress, address indexed collectionAddress, WeightFunction fn);
    event RewardsClaimed(
        address indexed vaultAddress,
        address indexed user,
        address indexed collectionAddress,
        uint256 amount,
        uint256 secondsInClaim
    );
    event RewardPerBlockUpdated(address indexed vault, uint128 rewardPerBlock);
    event VaultAdded(
        address indexed vaultAddress, address indexed cTokenAddress, address indexed lendingManagerAddress
    );
    event VaultRemoved(address indexed vaultAddress);

    error AddressZero();
    error CollectionNotWhitelisted(address collection);
    error CollectionAlreadyExists(address collection);
    error InvalidSignature();
    error ClaimExpired();
    error InvalidSecondsColl();
    error InvalidYieldSlice();
    error InsufficientYield();
    error ArrayLengthMismatch();
    error InvalidNonce();
    error VaultMismatch();
    error InvalidRewardSharePercentage(uint256 totalSharePercentage);
    error CollectionNotWhitelistedInVault(address vaultAddress, address collectionAddress);
    error CannotSetSignerToZeroAddress();
    error VaultNotRegistered(address vaultAddress);
    error CollectionAlreadyWhitelistedInVault(address vaultAddress, address collectionAddress);
    error VaultAlreadyRegistered(address vaultAddress);
    error InvalidCollectionInterface(address collectionAddress, bytes4 interfaceId);
    error LendingManagerNotSetForVault(address vaultAddress);
    error LendingManagerAssetMismatch(address vaultAsset, address lmAsset);

    // --- Vault Management ---
    function addVault(address vaultAddress_, address lendingManagerAddress_) external;
    function removeVault(address vaultAddress_) external;
    function vaults(address vaultAddress) external view returns (VaultInfo memory);

    // --- Collection Management ---
    function whitelistCollection(
        address vaultAddress,
        address collectionAddress,
        CollectionType collectionType,
        RewardBasis rewardBasis,
        uint16 sharePercentageBps
    ) external;
    function removeCollection(address vaultAddress, address collectionAddress) external;
    function updateCollectionPercentageShare(
        address vaultAddress,
        address collectionAddress,
        uint16 newSharePercentageBps
    ) external;
    function isCollectionWhitelisted(address vaultAddress, address collectionAddress) external view returns (bool);
    function collectionRewardBasis(address vaultAddress, address collectionAddress)
        external
        view
        returns (RewardBasis);
    function setWeightFunction(address vaultAddress, address collectionAddress, WeightFunction calldata weightFunction)
        external;

    // --- Reward & Weighting Configuration ---

    // --- User Information & Claims ---
    function userNonce(address vaultAddress, address userAddress) external view returns (uint64 nonce);
    function claimLazy(address vaultAddress, Claim[] calldata claims, bytes calldata signature) external;

    // --- Administrative Actions ---
    function updateTrustedSigner(address newSigner) external;
    function claimSigner() external view returns (address);
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
