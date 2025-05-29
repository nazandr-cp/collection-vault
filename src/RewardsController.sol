// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IRewardsController} from "./interfaces/IRewardsController.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

contract RewardsController is
    Initializable,
    IRewardsController,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    struct InternalVaultInfo {
        uint128 rewardPerBlock;
        uint128 globalRPW;
        uint128 totalWeight;
        uint64 lastUpdateBlock;
        uint256 lastAssetsBalance;
        address cToken;
    }

    bytes32 private constant CLAIM_TYPEHASH = keccak256(
        "Claim(address account,address collection,address vault,uint256 secondsUser,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint16 private constant MAX_REWARD_SHARE_PERCENTAGE = 10000;

    address internal _claimSigner;

    mapping(address => InternalVaultInfo) internal _vaultsData;
    mapping(address => mapping(address => uint256)) private _accountClaimNonces;
    mapping(address => mapping(address => IRewardsController.WeightFunction)) internal _collectionWeightFunctions;
    mapping(address => mapping(address => uint16)) internal _collectionRewardSharePercentage;
    mapping(address => uint16) internal _totalCollectionShareBps;
    mapping(address => mapping(address => IRewardsController.RewardBasis)) internal _collectionRewardBasis;
    mapping(address => mapping(address => IRewardsController.CollectionType)) internal _collectionType;
    mapping(address => mapping(address => bool)) internal _isCollectionWhitelisted;
    mapping(address => ILendingManager) internal _vaultLendingManagers;
    mapping(address => mapping(address => uint256)) internal _userSecondsClaimed;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address initialClaimSigner) public initializer {
        if (initialOwner == address(0) || initialClaimSigner == address(0)) {
            revert IRewardsController.AddressZero();
        }
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("RewardsController", "1");
        __Pausable_init();
        _claimSigner = initialClaimSigner;
    }

    function addVault(address vaultAddress_, address lendingManagerAddress_)
        external
        override(IRewardsController)
        onlyOwner
    {
        if (vaultAddress_ == address(0) || lendingManagerAddress_ == address(0)) {
            revert IRewardsController.AddressZero();
        }
        if (_vaultsData[vaultAddress_].lastUpdateBlock != 0) {
            revert IRewardsController.VaultAlreadyRegistered(vaultAddress_);
        }

        ILendingManager lendingManager = ILendingManager(lendingManagerAddress_);
        IERC4626 vault = IERC4626(vaultAddress_);
        address vaultAsset = vault.asset();
        address lmAsset = address(lendingManager.asset());

        if (vaultAsset != lmAsset) {
            revert IRewardsController.LendingManagerAssetMismatch(vaultAsset, lmAsset);
        }

        _vaultLendingManagers[vaultAddress_] = lendingManager;
        _vaultsData[vaultAddress_].lastUpdateBlock = uint64(block.number);
        _vaultsData[vaultAddress_].lastAssetsBalance = lendingManager.totalAssets();
        _vaultsData[vaultAddress_].cToken = vault.asset();

        emit VaultAdded(vaultAddress_, vault.asset(), lendingManagerAddress_);
    }

    function removeVault(address vaultAddress_) external override(IRewardsController) onlyOwner {
        if (vaultAddress_ == address(0)) {
            revert IRewardsController.AddressZero();
        }
        if (_vaultsData[vaultAddress_].lastUpdateBlock == 0) {
            revert IRewardsController.VaultNotRegistered(vaultAddress_);
        }

        delete _vaultsData[vaultAddress_];
        delete _vaultLendingManagers[vaultAddress_];

        emit VaultRemoved(vaultAddress_);
    }

    function vaults(address vaultAddress)
        external
        view
        override(IRewardsController)
        returns (IRewardsController.VaultInfo memory vaultInfo)
    {
        InternalVaultInfo storage internalVault = _vaultsData[vaultAddress];
        if (
            internalVault.lastUpdateBlock == 0 && internalVault.rewardPerBlock == 0 && internalVault.globalRPW == 0
                && internalVault.totalWeight == 0
        ) {
            revert IRewardsController.VaultNotRegistered(vaultAddress);
        }
        vaultInfo.lastUpdateBlock = uint32(internalVault.lastUpdateBlock);
        vaultInfo.cToken = internalVault.cToken;
    }

    function whitelistCollection(
        address vaultAddress,
        address collectionAddress,
        IRewardsController.CollectionType collectionType,
        IRewardsController.RewardBasis rewardBasis,
        uint16 sharePercentageBps
    ) external override(IRewardsController) onlyOwner {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IRewardsController.AddressZero();
        if (_vaultsData[vaultAddress].lastUpdateBlock == 0) revert VaultNotRegistered(vaultAddress);
        if (_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert CollectionAlreadyWhitelistedInVault(vaultAddress, collectionAddress);
        }
        if (
            collectionType == IRewardsController.CollectionType.ERC721
                || collectionType == IRewardsController.CollectionType.ERC1155
        ) {
            bytes4 interfaceIdNFT;
            if (collectionType == IRewardsController.CollectionType.ERC721) {
                interfaceIdNFT = type(IERC721).interfaceId;
            } else {
                interfaceIdNFT = type(IERC1155).interfaceId;
            }
            if (!ERC165Checker.supportsInterface(collectionAddress, interfaceIdNFT)) {
                revert IRewardsController.InvalidCollectionInterface(collectionAddress, interfaceIdNFT);
            }
        }
        if (_totalCollectionShareBps[vaultAddress] + sharePercentageBps > MAX_REWARD_SHARE_PERCENTAGE) {
            revert InvalidRewardSharePercentage(_totalCollectionShareBps[vaultAddress] + sharePercentageBps);
        }
        _collectionType[vaultAddress][collectionAddress] = collectionType;
        _collectionRewardBasis[vaultAddress][collectionAddress] = rewardBasis;
        _collectionRewardSharePercentage[vaultAddress][collectionAddress] = sharePercentageBps;
        _totalCollectionShareBps[vaultAddress] += sharePercentageBps;
        _isCollectionWhitelisted[vaultAddress][collectionAddress] = true;
        _collectionWeightFunctions[vaultAddress][collectionAddress] =
            IRewardsController.WeightFunction({fnType: IRewardsController.WeightFunctionType.LINEAR, p1: 0, p2: 0});
        emit NewCollectionWhitelisted(
            vaultAddress,
            collectionAddress,
            collectionType,
            rewardBasis,
            sharePercentageBps,
            _collectionWeightFunctions[vaultAddress][collectionAddress]
        );
    }

    function removeCollection(address vaultAddress, address collectionAddress)
        external
        override(IRewardsController)
        onlyOwner
    {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IRewardsController.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        uint16 sharePercentageBps = _collectionRewardSharePercentage[vaultAddress][collectionAddress];
        _totalCollectionShareBps[vaultAddress] -= sharePercentageBps;
        delete _isCollectionWhitelisted[vaultAddress][collectionAddress];
        delete _collectionType[vaultAddress][collectionAddress];
        delete _collectionRewardBasis[vaultAddress][collectionAddress];
        delete _collectionRewardSharePercentage[vaultAddress][collectionAddress];
        delete _collectionWeightFunctions[vaultAddress][collectionAddress];
        emit WhitelistCollectionRemoved(vaultAddress, collectionAddress);
    }

    function updateCollectionPercentageShare(
        address vaultAddress,
        address collectionAddress,
        uint16 newSharePercentageBps
    ) external override(IRewardsController) onlyOwner {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IRewardsController.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        uint16 oldSharePercentageBps = _collectionRewardSharePercentage[vaultAddress][collectionAddress];
        if (
            _totalCollectionShareBps[vaultAddress] - oldSharePercentageBps + newSharePercentageBps
                > MAX_REWARD_SHARE_PERCENTAGE
        ) {
            revert InvalidRewardSharePercentage(
                _totalCollectionShareBps[vaultAddress] - oldSharePercentageBps + newSharePercentageBps
            );
        }
        _totalCollectionShareBps[vaultAddress] =
            _totalCollectionShareBps[vaultAddress] - oldSharePercentageBps + newSharePercentageBps;
        _collectionRewardSharePercentage[vaultAddress][collectionAddress] = newSharePercentageBps;
        emit CollectionRewardShareUpdated(vaultAddress, collectionAddress, oldSharePercentageBps, newSharePercentageBps);
    }

    function setWeightFunction(
        address vaultAddress,
        address collectionAddress,
        IRewardsController.WeightFunction calldata weightFunction
    ) external override(IRewardsController) onlyOwner {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IRewardsController.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        _collectionWeightFunctions[vaultAddress][collectionAddress] = weightFunction;
        emit WeightFunctionSet(vaultAddress, collectionAddress, weightFunction);
    }

    function refreshRewardPerBlock(address forVault) external {
        if (forVault == address(0)) revert IRewardsController.AddressZero();
        if (_vaultsData[forVault].lastUpdateBlock == 0) {
            revert IRewardsController.VaultNotRegistered(forVault);
        }

        ILendingManager lendingManager = _vaultLendingManagers[forVault];
        if (address(lendingManager) == address(0)) {
            revert IRewardsController.LendingManagerNotSetForVault(forVault);
        }

        InternalVaultInfo storage vaultStore = _vaultsData[forVault];
        uint256 currentBalance = lendingManager.totalAssets();

        uint256 currentYield = 0;
        if (currentBalance >= vaultStore.lastAssetsBalance) {
            currentYield = currentBalance - vaultStore.lastAssetsBalance;
        }

        uint64 blocksDelta = uint64(block.number) - vaultStore.lastUpdateBlock;

        uint128 newRewardPerBlock = 0;
        if (blocksDelta > 0) {
            newRewardPerBlock = uint128(currentYield / blocksDelta);
        }

        vaultStore.rewardPerBlock = newRewardPerBlock;

        if (vaultStore.totalWeight > 0) {
            uint256 calculatedGlobalRPW = (uint256(newRewardPerBlock) * PRECISION_FACTOR) / vaultStore.totalWeight;
            if (calculatedGlobalRPW > type(uint128).max) {
                vaultStore.globalRPW = type(uint128).max;
            } else {
                vaultStore.globalRPW = uint128(calculatedGlobalRPW);
            }
        } else {
            vaultStore.globalRPW = 0;
        }

        vaultStore.lastUpdateBlock = uint64(block.number);
        vaultStore.lastAssetsBalance = currentBalance;

        emit RewardPerBlockUpdated(forVault, newRewardPerBlock);
    }

    function userNonce(address vaultAddress, address userAddress)
        external
        view
        override(IRewardsController)
        returns (uint64 nonce)
    {
        return uint64(_accountClaimNonces[vaultAddress][userAddress]);
    }

    function userSecondsClaimed(address vaultAddress, address userAddress) external view returns (uint256) {
        return _userSecondsClaimed[vaultAddress][userAddress];
    }

    function claimLazy(address vaultAddress, IRewardsController.Claim[] calldata claims, bytes calldata signature)
        external
        override(IRewardsController)
        nonReentrant
        whenNotPaused
    {
        bytes32 claimsHash = keccak256(abi.encode(claims));
        bytes32 digest = _hashTypedDataV4(claimsHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != _claimSigner || recoveredSigner == address(0)) {
            revert IRewardsController.InvalidSignature();
        }

        if (_vaultsData[vaultAddress].lastUpdateBlock == 0) revert VaultNotRegistered(vaultAddress);

        uint256 totalAmountToClaim = 0;
        uint256[] memory individualClaimAmounts = new uint256[](claims.length);

        for (uint256 i = 0; i < claims.length; i++) {
            IRewardsController.Claim calldata currentClaim = claims[i];
            address user = currentClaim.account;
            address collection = currentClaim.collection;

            if (user == address(0) || collection == address(0)) {
                revert IRewardsController.AddressZero();
            }

            if (block.timestamp > currentClaim.deadline) {
                revert IRewardsController.ClaimExpired();
            }

            uint256 currentNonce = _accountClaimNonces[vaultAddress][user];
            if (currentClaim.nonce != currentNonce) {
                revert IRewardsController.InvalidNonce();
            }
            _accountClaimNonces[vaultAddress][user]++;

            uint256 amountToClaimThisCollection = currentClaim.amount;
            individualClaimAmounts[i] = amountToClaimThisCollection;

            if (amountToClaimThisCollection > 0) {
                _userSecondsClaimed[vaultAddress][user] += currentClaim.secondsUser;
                totalAmountToClaim += amountToClaimThisCollection;
                emit RewardsClaimed(
                    vaultAddress, user, collection, amountToClaimThisCollection, currentClaim.secondsUser
                );
            }
        }

        if (totalAmountToClaim > 0) {
            ICollectionsVault vault = ICollectionsVault(vaultAddress);

            address[] memory collections = new address[](claims.length);
            uint256[] memory amounts = new uint256[](claims.length);

            for (uint256 i = 0; i < claims.length; i++) {
                collections[i] = claims[i].collection;
                amounts[i] = individualClaimAmounts[i];
            }

            vault.transferYieldBatch(collections, amounts, totalAmountToClaim, msg.sender);
        }
    }

    function collectionRewardBasis(address vaultAddress, address collectionAddress)
        external
        view
        override(IRewardsController)
        returns (IRewardsController.RewardBasis)
    {
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IRewardsController.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        return _collectionRewardBasis[vaultAddress][collectionAddress];
    }

    function isCollectionWhitelisted(address vaultAddress, address collectionAddress)
        external
        view
        override(IRewardsController)
        returns (bool)
    {
        return _isCollectionWhitelisted[vaultAddress][collectionAddress];
    }

    function updateTrustedSigner(address newSigner) external override(IRewardsController) onlyOwner {
        if (newSigner == address(0)) {
            revert IRewardsController.CannotSetSignerToZeroAddress();
        }
        address oldSigner = _claimSigner;
        _claimSigner = newSigner;
        emit TrustedSignerUpdated(oldSigner, newSigner, msg.sender);
    }

    function claimSigner() external view override(IRewardsController) returns (address) {
        return _claimSigner;
    }

    function pause() external override(IRewardsController) onlyOwner {
        super._pause();
    }

    function unpause() external override(IRewardsController) onlyOwner {
        super._unpause();
    }

    function paused() public view override(IRewardsController, PausableUpgradeable) returns (bool) {
        return super.paused();
    }
}
