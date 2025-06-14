// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {IDebtSubsidizer} from "./interfaces/IDebtSubsidizer.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {IEpochManager} from "./interfaces/IEpochManager.sol";
import {ICollectionRegistry} from "./interfaces/ICollectionRegistry.sol";

contract DebtSubsidizer is
    Initializable,
    IDebtSubsidizer,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    struct InternalVaultInfo {
        address cToken;
    }

    uint16 private constant MAX_YIELD_SHARE_PERCENTAGE = 10000;
    uint16 private constant MIN_YIELD_SHARE_PERCENTAGE = 100;

    mapping(address => InternalVaultInfo) internal _vaultsData;
    mapping(address => bytes32) internal _merkleRoots; // Vault address => Merkle Root
    mapping(bytes32 => bool) internal _claimedLeaves; // Merkle Leaf => Claimed status

    mapping(address => mapping(address => IDebtSubsidizer.WeightFunction)) internal _collectionWeightFunctions;
    mapping(address => mapping(address => uint16)) internal _collectionYieldSharePercentage;
    mapping(address => uint16) internal _totalCollectionYieldShareBps;
    mapping(address => mapping(address => IDebtSubsidizer.CollectionType)) internal _collectionType;
    mapping(address => mapping(address => bool)) internal _isCollectionWhitelisted;
    mapping(address => ILendingManager) internal _vaultLendingManagers;
    mapping(address => mapping(address => uint256)) internal _userSecondsClaimed;
    mapping(address => uint256) internal _userTotalSecondsClaimed;
    ICollectionRegistry public collectionRegistry;

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner, address registry) public initializer {
        if (initialOwner == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (registry == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        __Ownable_init(initialOwner);
        __ReentrancyGuard_init();
        __Pausable_init();
        collectionRegistry = ICollectionRegistry(registry);
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
        _collectionYieldSharePercentage[vaultAddress][collectionAddress] = sharePercentageBps;
        _totalCollectionYieldShareBps[vaultAddress] += sharePercentageBps;
        _isCollectionWhitelisted[vaultAddress][collectionAddress] = true;
        collectionRegistry.setYieldShare(collectionAddress, sharePercentageBps);
        _collectionWeightFunctions[vaultAddress][collectionAddress] =
            IDebtSubsidizer.WeightFunction({fnType: IDebtSubsidizer.WeightFunctionType.LINEAR, p1: 0, p2: 0});
        emit NewCollectionWhitelisted(
            vaultAddress,
            collectionAddress,
            collectionType,
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
        delete _collectionYieldSharePercentage[vaultAddress][collectionAddress];
        collectionRegistry.setYieldShare(collectionAddress, 0);
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
        collectionRegistry.setYieldShare(collectionAddress, newSharePercentageBps);
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

    function claimSubsidy(address vaultAddress, IDebtSubsidizer.ClaimData calldata claim)
        external
        override(IDebtSubsidizer)
        nonReentrant
        whenNotPaused
    {
        if (_vaultsData[vaultAddress].cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        }

        bytes32 merkleRoot = _merkleRoots[vaultAddress];
        if (merkleRoot == bytes32(0)) {
            revert IDebtSubsidizer.MerkleRootNotSet();
        }

        address recipient = claim.recipient;
        address collection = claim.collection;
        uint256 amountToSubsidize = claim.amount;

        if (recipient == address(0) || collection == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }

        bytes32 leaf = keccak256(abi.encodePacked(recipient, collection, amountToSubsidize));

        if (_claimedLeaves[leaf]) {
            revert IDebtSubsidizer.LeafAlreadyClaimed();
        }

        if (!MerkleProof.verify(claim.merkleProof, merkleRoot, leaf)) {
            revert IDebtSubsidizer.InvalidMerkleProof();
        }

        _claimedLeaves[leaf] = true;

        if (amountToSubsidize > 0) {
            IEpochManager em = ICollectionsVault(vaultAddress).epochManager();
            uint256 epochId = em.getCurrentEpochId();
            uint256 remainingYield = ICollectionsVault(vaultAddress).getEpochYieldAllocated(epochId);
            if (amountToSubsidize > remainingYield) {
                revert IDebtSubsidizer.InsufficientYield();
            }

            _userTotalSecondsClaimed[recipient] += amountToSubsidize;
            emit SubsidyClaimed(vaultAddress, recipient, collection, amountToSubsidize);

            ICollectionsVault(vaultAddress).repayBorrowBehalf(amountToSubsidize, recipient);
        }
    }

    function updateMerkleRoot(address vaultAddress, bytes32 merkleRoot_) external override(IDebtSubsidizer) onlyOwner {
        if (vaultAddress == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (_vaultsData[vaultAddress].cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        }
        _merkleRoots[vaultAddress] = merkleRoot_;
        emit MerkleRootUpdated(vaultAddress, merkleRoot_, msg.sender);
    }

    function isCollectionWhitelisted(address vaultAddress, address collectionAddress)
        external
        view
        override(IDebtSubsidizer)
        returns (bool)
    {
        return _isCollectionWhitelisted[vaultAddress][collectionAddress];
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

    function userSecondsClaimed(address user) external view returns (uint256) {
        if (user == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        return _userTotalSecondsClaimed[user];
    }
}
