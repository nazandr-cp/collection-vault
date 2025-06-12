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

import {IDebtSubsidizer} from "./interfaces/IDebtSubsidizer.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

contract DebtSubsidizer is
    Initializable,
    IDebtSubsidizer,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    // Event definitions
    // Duplicated events are removed as they are defined in IDebtSubsidizer.sol
    // VaultAdded, VaultRemoved, NewCollectionWhitelisted, WhitelistCollectionRemoved,
    // CollectionYieldShareUpdated, TrustedSignerUpdated, DebtSubsidized

    event WeightFunctionConfigUpdated( // This event is specific to the implementation details
        address indexed vaultAddress,
        address indexed collectionAddress,
        IDebtSubsidizer.WeightFunction oldWeightFunction,
        IDebtSubsidizer.WeightFunction newWeightFunction
    );
    // Note: Paused and Unpaused events are inherited from PausableUpgradeable

    struct InternalVaultInfo {
        address cToken;
    }

    bytes32 private constant SUBSIDY_TYPEHASH = keccak256(
        "Subsidy(address account,address collection,address vault,uint256 amount,uint256 nonce,uint256 deadline)"
    );
    uint16 private constant MAX_YIELD_SHARE_PERCENTAGE = 10000;

    address internal _subsidySigner;

    mapping(address => InternalVaultInfo) internal _vaultsData;
    mapping(address => mapping(address => uint256)) private _accountNonces;
    mapping(address => mapping(address => IDebtSubsidizer.WeightFunction)) internal _collectionWeightFunctions;
    mapping(address => mapping(address => uint16)) internal _collectionYieldSharePercentage;
    mapping(address => uint16) internal _totalCollectionYieldShareBps;
    mapping(address => mapping(address => IDebtSubsidizer.RewardBasis)) internal _collectionRewardBasis;
    mapping(address => mapping(address => IDebtSubsidizer.CollectionType)) internal _collectionType;
    mapping(address => mapping(address => bool)) internal _isCollectionWhitelisted;
    mapping(address => ILendingManager) internal _vaultLendingManagers;
    mapping(address => mapping(address => uint256)) internal _userSecondsClaimed; // Original mapping, currently unused for writes
    mapping(address => uint256) internal _userTotalSecondsClaimed; // New mapping for userSecondsClaimed()

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address initialSubsidySigner) public initializer {
        if (initialOwner == address(0) || initialSubsidySigner == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __EIP712_init("DebtSubsidizer", "1");
        __Pausable_init();
        _subsidySigner = initialSubsidySigner;
    }

    function addVault(address vaultAddress_, address lendingManagerAddress_)
        external
        override(IDebtSubsidizer)
        onlyOwner
    {
        if (vaultAddress_ == address(0) || lendingManagerAddress_ == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (_vaultsData[vaultAddress_].cToken != address(0)) {
            revert IDebtSubsidizer.VaultAlreadyRegistered(vaultAddress_);
        }

        ILendingManager lendingManager = ILendingManager(lendingManagerAddress_);
        IERC4626 vaultToken = IERC4626(vaultAddress_);
        address cTokenAddress = vaultToken.asset();
        address lmAsset = address(lendingManager.asset());

        if (cTokenAddress != lmAsset) {
            revert IDebtSubsidizer.LendingManagerAssetMismatch(cTokenAddress, lmAsset);
        }

        _vaultLendingManagers[vaultAddress_] = lendingManager;
        _vaultsData[vaultAddress_].cToken = cTokenAddress;

        emit VaultAdded(vaultAddress_, cTokenAddress, lendingManagerAddress_);
    }

    function removeVault(address vaultAddress_) external override(IDebtSubsidizer) onlyOwner {
        if (vaultAddress_ == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (_vaultsData[vaultAddress_].cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress_);
        }

        delete _vaultsData[vaultAddress_];
        delete _vaultLendingManagers[vaultAddress_];

        emit VaultRemoved(vaultAddress_);
    }

    function vault(address vaultAddress)
        external
        view
        override(IDebtSubsidizer)
        returns (IDebtSubsidizer.VaultInfo memory vaultInfo_)
    {
        InternalVaultInfo storage internalVault = _vaultsData[vaultAddress];
        if (internalVault.cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        }
        vaultInfo_.cToken = internalVault.cToken;
        vaultInfo_.lendingManager = address(_vaultLendingManagers[vaultAddress]);
    }

    function whitelistCollection(
        address vaultAddress,
        address collectionAddress,
        IDebtSubsidizer.CollectionType collectionType,
        IDebtSubsidizer.RewardBasis rewardBasis,
        uint16 sharePercentageBps
    ) external override(IDebtSubsidizer) onlyOwner {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IDebtSubsidizer.AddressZero();
        if (_vaultsData[vaultAddress].cToken == address(0)) revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        if (_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionAlreadyWhitelistedInVault(vaultAddress, collectionAddress);
        }
        if (
            collectionType == IDebtSubsidizer.CollectionType.ERC721
                || collectionType == IDebtSubsidizer.CollectionType.ERC1155
        ) {
            bytes4 interfaceIdNFT;
            if (collectionType == IDebtSubsidizer.CollectionType.ERC721) {
                interfaceIdNFT = type(IERC721).interfaceId;
            } else {
                interfaceIdNFT = type(IERC1155).interfaceId;
            }
            if (!ERC165Checker.supportsInterface(collectionAddress, interfaceIdNFT)) {
                revert IDebtSubsidizer.InvalidCollectionInterface(collectionAddress, interfaceIdNFT);
            }
        }
        if (_totalCollectionYieldShareBps[vaultAddress] + sharePercentageBps > MAX_YIELD_SHARE_PERCENTAGE) {
            revert IDebtSubsidizer.InvalidYieldSharePercentage(
                _totalCollectionYieldShareBps[vaultAddress] + sharePercentageBps
            );
        }
        _collectionType[vaultAddress][collectionAddress] = collectionType;
        _collectionRewardBasis[vaultAddress][collectionAddress] = rewardBasis;
        _collectionYieldSharePercentage[vaultAddress][collectionAddress] = sharePercentageBps;
        _totalCollectionYieldShareBps[vaultAddress] += sharePercentageBps;
        _isCollectionWhitelisted[vaultAddress][collectionAddress] = true;
        _collectionWeightFunctions[vaultAddress][collectionAddress] =
            IDebtSubsidizer.WeightFunction({fnType: IDebtSubsidizer.WeightFunctionType.LINEAR, p1: 0, p2: 0});
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
        override(IDebtSubsidizer)
        onlyOwner
    {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IDebtSubsidizer.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        uint16 sharePercentageBps = _collectionYieldSharePercentage[vaultAddress][collectionAddress];
        _totalCollectionYieldShareBps[vaultAddress] -= sharePercentageBps;
        delete _isCollectionWhitelisted[vaultAddress][collectionAddress];
        delete _collectionType[vaultAddress][collectionAddress];
        delete _collectionRewardBasis[vaultAddress][collectionAddress];
        delete _collectionYieldSharePercentage[vaultAddress][collectionAddress];
        delete _collectionWeightFunctions[vaultAddress][collectionAddress];
        emit WhitelistCollectionRemoved(vaultAddress, collectionAddress);
    }

    function updateCollectionPercentageShare(
        address vaultAddress,
        address collectionAddress,
        uint16 newSharePercentageBps
    ) external override(IDebtSubsidizer) onlyOwner {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IDebtSubsidizer.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        uint16 oldSharePercentageBps = _collectionYieldSharePercentage[vaultAddress][collectionAddress];
        if (
            _totalCollectionYieldShareBps[vaultAddress] - oldSharePercentageBps + newSharePercentageBps
                > MAX_YIELD_SHARE_PERCENTAGE
        ) {
            revert IDebtSubsidizer.InvalidYieldSharePercentage(
                _totalCollectionYieldShareBps[vaultAddress] - oldSharePercentageBps + newSharePercentageBps
            );
        }
        _totalCollectionYieldShareBps[vaultAddress] =
            _totalCollectionYieldShareBps[vaultAddress] - oldSharePercentageBps + newSharePercentageBps;
        _collectionYieldSharePercentage[vaultAddress][collectionAddress] = newSharePercentageBps;
        emit CollectionYieldShareUpdated(vaultAddress, collectionAddress, oldSharePercentageBps, newSharePercentageBps);
    }

    function setWeightFunction(
        address vaultAddress,
        address collectionAddress,
        IDebtSubsidizer.WeightFunction calldata newWeightFunction_
    ) external override(IDebtSubsidizer) onlyOwner {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IDebtSubsidizer.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        IDebtSubsidizer.WeightFunction memory oldWeightFunction =
            _collectionWeightFunctions[vaultAddress][collectionAddress];
        _collectionWeightFunctions[vaultAddress][collectionAddress] = newWeightFunction_;
        emit WeightFunctionConfigUpdated(vaultAddress, collectionAddress, oldWeightFunction, newWeightFunction_);
    }

    function userNonce(address vaultAddress, address userAddress)
        external
        view
        override(IDebtSubsidizer)
        returns (uint64 nonce)
    {
        return uint64(_accountNonces[vaultAddress][userAddress]);
    }

    function getCollectionWeightFunction(address vaultAddress, address collectionAddress)
        external
        view
        returns (IDebtSubsidizer.WeightFunction memory)
    {
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        return _collectionWeightFunctions[vaultAddress][collectionAddress];
    }

    function subsidize(address vaultAddress, IDebtSubsidizer.Subsidy[] calldata subsidies, bytes calldata signature)
        external
        override(IDebtSubsidizer)
        nonReentrant
        whenNotPaused
    {
        bytes32 subsidiesHash = keccak256(abi.encode(subsidies));
        bytes32 digest = _hashTypedDataV4(subsidiesHash);
        address recoveredSigner = ECDSA.recover(digest, signature);

        if (recoveredSigner != _subsidySigner || recoveredSigner == address(0)) {
            revert IDebtSubsidizer.InvalidSignature();
        }

        if (_vaultsData[vaultAddress].cToken == address(0)) revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);

        uint256 numSubsidies = subsidies.length;
        address[] memory tempCollections = new address[](numSubsidies);
        uint256[] memory tempAmounts = new uint256[](numSubsidies);
        address[] memory tempBorrowers = new address[](numSubsidies);
        uint256 actualSubsidyCountForBatch = 0;
        uint256 totalAmountToSubsidize = 0;

        for (uint256 i = 0; i < numSubsidies; i++) {
            IDebtSubsidizer.Subsidy calldata currentSubsidy = subsidies[i];
            address user = currentSubsidy.account;
            address collection = currentSubsidy.collection;
            address subsidyVault = currentSubsidy.vault;
            uint256 amountToSubsidize = currentSubsidy.amount;

            if (user == address(0) || collection == address(0) || subsidyVault == address(0)) {
                revert IDebtSubsidizer.AddressZero();
            }

            if (subsidyVault != vaultAddress) {
                revert IDebtSubsidizer.VaultMismatch();
            }

            if (block.timestamp > currentSubsidy.deadline) {
                revert IDebtSubsidizer.ClaimExpired();
            }

            uint256 currentNonce = _accountNonces[vaultAddress][user];
            if (currentSubsidy.nonce != currentNonce) {
                revert IDebtSubsidizer.InvalidNonce();
            }
            _accountNonces[vaultAddress][user]++;

            if (amountToSubsidize > 0) {
                tempCollections[actualSubsidyCountForBatch] = collection;
                tempAmounts[actualSubsidyCountForBatch] = amountToSubsidize;
                tempBorrowers[actualSubsidyCountForBatch] = user;
                actualSubsidyCountForBatch++;
                totalAmountToSubsidize += amountToSubsidize;
                _userTotalSecondsClaimed[user] += amountToSubsidize; // Update total seconds claimed for the user

                emit DebtSubsidized(vaultAddress, user, collection, amountToSubsidize);
            }
        }

        if (actualSubsidyCountForBatch > 0) {
            address[] memory collectionsToRepay = new address[](actualSubsidyCountForBatch);
            uint256[] memory amountsToRepay = new uint256[](actualSubsidyCountForBatch);
            address[] memory borrowersToRepay = new address[](actualSubsidyCountForBatch);

            for (uint256 j = 0; j < actualSubsidyCountForBatch; j++) {
                collectionsToRepay[j] = tempCollections[j];
                amountsToRepay[j] = tempAmounts[j];
                borrowersToRepay[j] = tempBorrowers[j];
            }

            ICollectionsVault(vaultAddress).repayBorrowBehalfBatch(
                collectionsToRepay, amountsToRepay, borrowersToRepay, totalAmountToSubsidize
            );
        }
    }

    function collectionRewardBasis(address vaultAddress, address collectionAddress)
        external
        view
        override(IDebtSubsidizer)
        returns (IDebtSubsidizer.RewardBasis)
    {
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        return _collectionRewardBasis[vaultAddress][collectionAddress];
    }

    function isCollectionWhitelisted(address vaultAddress, address collectionAddress)
        external
        view
        override(IDebtSubsidizer)
        returns (bool)
    {
        return _isCollectionWhitelisted[vaultAddress][collectionAddress];
    }

    function updateTrustedSigner(address newSigner) external override(IDebtSubsidizer) onlyOwner {
        if (newSigner == address(0)) {
            revert IDebtSubsidizer.CannotSetSignerToZeroAddress();
        }
        address oldSigner = _subsidySigner;
        _subsidySigner = newSigner;
        emit TrustedSignerUpdated(oldSigner, newSigner, msg.sender);
    }

    function subsidySigner() external view override(IDebtSubsidizer) returns (address) {
        return _subsidySigner;
    }

    function pause() external override(IDebtSubsidizer) onlyOwner {
        super._pause();
    }

    function unpause() external override(IDebtSubsidizer) onlyOwner {
        super._unpause();
    }

    function paused() public view override(IDebtSubsidizer, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    // --- Getter for claimed seconds ---
    function userSecondsClaimed(address user) external view returns (uint256) {
        if (user == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        return _userTotalSecondsClaimed[user];
    }

    function getDomainSeparator() public view returns (bytes32) {
        return _hashTypedDataV4(0); // This is how EIP712Upgradeable calculates the domain separator
    }
}
