/* SPDX-License-Identifier: UNLICENSED */
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";

abstract contract RewardsController is
    Initializable,
    IRewardsController,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    struct CollInfo {
        uint128 accRPS;
        uint128 lastSeconds;
    }

    struct UserInfo {
        mapping(address => uint128) secondsPaid;
        uint128 nonce;
    }

    bytes32 private constant CLAIM_TYPEHASH = keccak256(
        "Claim(address account,address collection,uint256 secondsUser,uint256 secondsColl,uint256 incRPS,uint256 yieldSlice,uint256 nonce,uint256 deadline)"
    );
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint16 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000;

    ICollectionsVault internal _vault;
    address internal immutable _oracle;

    uint256 internal _lastAssets;
    uint128 internal _yieldLeft;
    mapping(address => CollInfo) internal _coll;
    mapping(address => UserInfo) internal _user;
    mapping(address => IRewardsController.RewardBasis) internal _collectionRewardBasis;
    mapping(address => uint16) internal _collectionRewardSharePercentage;

    constructor(address oracleAddress_) {
        if (oracleAddress_ == address(0)) revert IRewardsController.AddressZero();
        _oracle = oracleAddress_;
        _disableInitializers();
    }

    function initialize(address initialOwner, address vaultAddress_) public initializer {
        if (initialOwner == address(0)) {
            revert IRewardsController.AddressZero();
        }
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("CollectionRewards", "1");
        __Pausable_init();

        if (vaultAddress_ == address(0)) {
            revert IRewardsController.AddressZero();
        }
        _vault = ICollectionsVault(vaultAddress_);

        address vaultAsset_ = IERC4626(vaultAddress_).asset();
        if (vaultAsset_ == address(0)) revert VaultMismatch();

        _lastAssets = _vault.totalAssets();
    }

    function _refreshYield() internal {
        uint256 currentTotalAssets = _vault.totalAssets();
        if (currentTotalAssets >= _lastAssets) {
            uint256 newYield = currentTotalAssets - _lastAssets;
            uint256 tempYieldLeft = uint256(_yieldLeft) + newYield;
            if (tempYieldLeft > type(uint128).max) {
                _yieldLeft = type(uint128).max;
            } else {
                _yieldLeft = uint128(tempYieldLeft);
            }
        }
        _lastAssets = currentTotalAssets;
    }

    function _hashClaim(IRewardsController.Claim calldata claim) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLAIM_TYPEHASH,
                    claim.account,
                    claim.collection,
                    claim.secondsUser,
                    claim.secondsColl,
                    claim.incRPS,
                    claim.yieldSlice,
                    claim.nonce,
                    claim.deadline
                )
            )
        );
    }

    function oracle() external view override returns (address) {
        return _oracle;
    }

    function vault() external view override returns (ICollectionsVault) {
        return _vault;
    }

    function lastAssets() external view override returns (uint256) {
        return _lastAssets;
    }

    function yieldLeft() external view override returns (uint128) {
        return _yieldLeft;
    }

    function coll(address collectionAddress) external view override returns (uint128 accRPS, uint128 lastSeconds) {
        CollInfo storage c = _coll[collectionAddress];
        return (c.accRPS, c.lastSeconds);
    }

    function userNonce(address userAddress) external view override returns (uint128 nonce) {
        return _user[userAddress].nonce;
    }

    function userSecondsPaid(address userAddress, address collectionAddress)
        external
        view
        override
        returns (uint128 secondsPaid)
    {
        return _user[userAddress].secondsPaid[collectionAddress];
    }

    function paused() public view override(IRewardsController, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    function previewClaim(IRewardsController.Claim[] calldata claims)
        external
        view
        override
        returns (uint256 totalDue)
    {
        totalDue = 0;
        for (uint256 i = 0; i < claims.length; i++) {
            IRewardsController.Claim calldata currentClaim = claims[i];
            if (currentClaim.account == address(0) || currentClaim.collection == address(0)) continue;
            CollInfo storage collectionInfo = _coll[currentClaim.collection];
            uint128 currentAccRPS = collectionInfo.accRPS;
            uint128 secondsPaidForCollection = _user[currentClaim.account].secondsPaid[currentClaim.collection];
            if (currentClaim.secondsUser > secondsPaidForCollection) {
                uint256 dueForClaim =
                    ((currentClaim.secondsUser - secondsPaidForCollection) * currentAccRPS) / PRECISION_FACTOR;
                totalDue += dueForClaim;
            }
        }
        return totalDue;
    }

    function claimLazy(IRewardsController.Claim[] calldata claims, bytes[] calldata signatures)
        external
        override
        nonReentrant
        whenNotPaused
    {
        if (claims.length != signatures.length) revert IRewardsController.ArrayLengthMismatch();

        _refreshYield();

        uint256 numClaimsProcessed = 0;

        // Temporary storage for aggregation. Max size is claims.length.
        address[] memory uniqueCollectionsForBatch = new address[](claims.length);
        uint256[] memory amountsForUniqueCollections = new uint256[](claims.length);
        uint256 uniqueCollectionsCount = 0;

        for (uint256 i = 0; i < claims.length; i++) {
            IRewardsController.Claim calldata currentClaim = claims[i];
            bytes calldata signature = signatures[i];

            bytes32 digest = _hashClaim(currentClaim);
            address recoveredSigner = ECDSA.recover(digest, signature);

            if (recoveredSigner != _oracle || recoveredSigner == address(0)) {
                revert IRewardsController.InvalidSignature();
            }

            if (block.timestamp > currentClaim.deadline) {
                revert IRewardsController.ClaimExpired();
            }

            if (currentClaim.nonce != _user[currentClaim.account].nonce) {
                revert IRewardsController.InvalidNonce(currentClaim.nonce, _user[currentClaim.account].nonce);
            }

            if (currentClaim.incRPS > 0) {
                CollInfo storage collectionInfo = _coll[currentClaim.collection];
                if (currentClaim.secondsColl <= collectionInfo.lastSeconds) {
                    revert IRewardsController.InvalidSecondsColl();
                }

                uint256 deltaSeconds = currentClaim.secondsColl - collectionInfo.lastSeconds;
                uint256 calculatedSlice = (currentClaim.incRPS * deltaSeconds) / PRECISION_FACTOR;

                if (currentClaim.yieldSlice != calculatedSlice) {
                    revert IRewardsController.InvalidYieldSlice();
                }

                if (currentClaim.yieldSlice > _yieldLeft) {
                    revert IRewardsController.InsufficientYield();
                }

                unchecked {
                    collectionInfo.accRPS += uint128(currentClaim.incRPS);
                    _yieldLeft -= uint128(currentClaim.yieldSlice); // Semicolon added
                }
                collectionInfo.lastSeconds = uint128(currentClaim.secondsColl);
            }

            uint128 secondsPaidForCollection = _user[currentClaim.account].secondsPaid[currentClaim.collection];
            uint256 dueForClaim = 0;
            if (currentClaim.secondsUser > secondsPaidForCollection) {
                dueForClaim = (
                    (currentClaim.secondsUser - secondsPaidForCollection) * _coll[currentClaim.collection].accRPS
                ) / PRECISION_FACTOR;
            }

            _user[currentClaim.account].secondsPaid[currentClaim.collection] = uint128(currentClaim.secondsUser);
            uint256 newNonceAfterThisClaim;
            unchecked {
                _user[currentClaim.account].nonce++;
                newNonceAfterThisClaim = _user[currentClaim.account].nonce;
            }

            emit RewardsClaimedForLazy(
                currentClaim.account,
                currentClaim.collection,
                dueForClaim,
                currentClaim.nonce, // Nonce used for this claim
                currentClaim.secondsUser,
                currentClaim.secondsColl,
                currentClaim.incRPS,
                currentClaim.yieldSlice
            );
            numClaimsProcessed++;

            if (dueForClaim > 0) {
                address collectionAddress = currentClaim.collection;
                bool collectionFoundInBatch = false;
                uint256 foundAtIndex = 0;
                for (uint256 j = 0; j < uniqueCollectionsCount; j++) {
                    if (uniqueCollectionsForBatch[j] == collectionAddress) {
                        collectionFoundInBatch = true;
                        foundAtIndex = j;
                        break;
                    }
                }

                if (collectionFoundInBatch) {
                    amountsForUniqueCollections[foundAtIndex] += dueForClaim;
                } else {
                    if (uniqueCollectionsCount < claims.length) {
                        uniqueCollectionsForBatch[uniqueCollectionsCount] = collectionAddress;
                        amountsForUniqueCollections[uniqueCollectionsCount] = dueForClaim;
                        uniqueCollectionsCount++;
                    }
                }
            }
        }

        uint256 totalAmountForBatch = 0;
        if (uniqueCollectionsCount > 0) {
            address[] memory finalCollectionsToBatch = new address[](uniqueCollectionsCount);
            uint256[] memory finalAmountsToBatch = new uint256[](uniqueCollectionsCount);

            for (uint256 k = 0; k < uniqueCollectionsCount; k++) {
                finalCollectionsToBatch[k] = uniqueCollectionsForBatch[k];
                finalAmountsToBatch[k] = amountsForUniqueCollections[k];
                totalAmountForBatch += amountsForUniqueCollections[k];
            }

            if (totalAmountForBatch > 0) {
                _vault.transferYieldBatch(finalCollectionsToBatch, finalAmountsToBatch, totalAmountForBatch, msg.sender);
            }
        }

        if (numClaimsProcessed > 0) {
            emit BatchRewardsClaimedForLazy(msg.sender, totalAmountForBatch, uniqueCollectionsCount);
        }
    }

    function pause() external override onlyOwner {
        _pause();
    }

    function unpause() external override onlyOwner {
        _unpause();
    }

    uint256[30] private __gap;
}
