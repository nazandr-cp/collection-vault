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
    mapping(address => mapping(address => uint256)) internal _claimedTotals; // vault => user => total claimed

    mapping(address => mapping(address => bool)) internal _isCollectionWhitelisted;
    mapping(address => address[]) internal _vaultWhitelistedCollections; // vault => array of whitelisted collections
    mapping(address => mapping(address => uint256)) internal _userSecondsClaimed;
    mapping(address => uint256) internal _userTotalSecondsClaimed;
    ICollectionRegistry public collectionRegistry;

    uint256 public totalSubsidyPool;
    uint256 public totalSubsidiesRemaining;
    uint256 public totalEligibleUsers;
    mapping(address => bool) public eligibleUsers;

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

        address[] memory whitelistedCollections = _vaultWhitelistedCollections[vaultAddress_];
        for (uint256 i = 0; i < whitelistedCollections.length; i++) {
            delete _isCollectionWhitelisted[vaultAddress_][whitelistedCollections[i]];
        }
        delete _vaultWhitelistedCollections[vaultAddress_];

        delete _vaultsData[vaultAddress_];

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
    }

    function whitelistCollection(address vaultAddress, address collectionAddress)
        external
        override(IDebtSubsidizer)
        onlyOwner
    {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IDebtSubsidizer.AddressZero();
        if (_vaultsData[vaultAddress].cToken == address(0)) revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        if (_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionAlreadyWhitelistedInVault(vaultAddress, collectionAddress);
        }

        _isCollectionWhitelisted[vaultAddress][collectionAddress] = true;
        _vaultWhitelistedCollections[vaultAddress].push(collectionAddress);

        emit NewCollectionWhitelisted(vaultAddress, collectionAddress);
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

        delete _isCollectionWhitelisted[vaultAddress][collectionAddress];

        // Remove from the whitelisted collections array
        address[] storage collections = _vaultWhitelistedCollections[vaultAddress];
        for (uint256 i = 0; i < collections.length; i++) {
            if (collections[i] == collectionAddress) {
                collections[i] = collections[collections.length - 1];
                collections.pop();
                break;
            }
        }

        emit WhitelistCollectionRemoved(vaultAddress, collectionAddress);
    }

    function _claimSubsidy(address vaultAddress, IDebtSubsidizer.ClaimData calldata claim) internal {
        if (_vaultsData[vaultAddress].cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        }

        bytes32 merkleRoot = _merkleRoots[vaultAddress];
        if (merkleRoot == bytes32(0)) {
            revert IDebtSubsidizer.MerkleRootNotSet();
        }

        address recipient = claim.recipient;
        uint256 newTotal = claim.totalEarned;

        if (recipient == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }

        bytes32 leaf = keccak256(abi.encodePacked(recipient, newTotal));

        if (!MerkleProof.verify(claim.merkleProof, merkleRoot, leaf)) {
            revert IDebtSubsidizer.InvalidMerkleProof();
        }

        uint256 prevClaimed = _claimedTotals[vaultAddress][recipient];
        if (newTotal <= prevClaimed) {
            revert IDebtSubsidizer.AlreadyClaimed();
        }

        uint256 amountToSubsidize = newTotal - prevClaimed;
        _claimedTotals[vaultAddress][recipient] = newTotal;

        if (amountToSubsidize > 0) {
            IEpochManager em = ICollectionsVault(vaultAddress).epochManager();
            uint256 epochId = em.getCurrentEpochId();
            uint256 remainingYield = ICollectionsVault(vaultAddress).getEpochYieldAllocated(epochId);
            if (amountToSubsidize > remainingYield) {
                revert IDebtSubsidizer.InsufficientYield();
            }

            // Check subsidy pool availability
            if (totalSubsidiesRemaining < amountToSubsidize) {
                revert IDebtSubsidizer.InsufficientYield();
            }

            _userTotalSecondsClaimed[recipient] += amountToSubsidize;

            // Update subsidy pool tracking
            totalSubsidiesRemaining -= amountToSubsidize;

            // Add user to eligible users if not already
            if (!eligibleUsers[recipient]) {
                eligibleUsers[recipient] = true;
                totalEligibleUsers++;
                emit EligibleUserCountUpdated(totalEligibleUsers, true, recipient, block.timestamp);
            }

            emit SubsidyClaimed(vaultAddress, recipient, amountToSubsidize);

            ICollectionsVault(vaultAddress).repayBorrowBehalf(amountToSubsidize, recipient);
        }
    }

    function claimSubsidy(address vaultAddress, IDebtSubsidizer.ClaimData calldata claim)
        external
        override(IDebtSubsidizer)
        nonReentrant
        whenNotPaused
    {
        _claimSubsidy(vaultAddress, claim);
    }

    function claimAllSubsidies(address[] calldata vaultAddresses, IDebtSubsidizer.ClaimData[] calldata claims)
        external
        override(IDebtSubsidizer)
        nonReentrant
        whenNotPaused
    {
        uint256 len = vaultAddresses.length;
        if (len != claims.length) {
            revert IDebtSubsidizer.ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < len;) {
            _claimSubsidy(vaultAddresses[i], claims[i]);
            unchecked {
                ++i;
            }
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

    function initializeSubsidyPool(uint256 poolAmount) external onlyOwner {
        require(poolAmount > 0, "Pool amount must be greater than zero");
        totalSubsidyPool = poolAmount;
        totalSubsidiesRemaining = poolAmount;
        emit SubsidyPoolInitialized(poolAmount, block.timestamp);
    }

    function updateSubsidyPool(uint256 newPoolAmount) external onlyOwner {
        require(newPoolAmount >= 0, "Pool amount cannot be negative");
        uint256 oldAmount = totalSubsidyPool;
        totalSubsidyPool = newPoolAmount;
        totalSubsidiesRemaining = newPoolAmount;
        emit SubsidyPoolUpdated(oldAmount, newPoolAmount, block.timestamp);
    }

    function addEligibleUser(address user) external onlyOwner {
        if (user == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (!eligibleUsers[user]) {
            eligibleUsers[user] = true;
            totalEligibleUsers++;
            emit EligibleUserCountUpdated(totalEligibleUsers, true, user, block.timestamp);
        }
    }

    function removeEligibleUser(address user) external onlyOwner {
        if (user == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (eligibleUsers[user]) {
            eligibleUsers[user] = false;
            totalEligibleUsers--;
            emit EligibleUserCountUpdated(totalEligibleUsers, false, user, block.timestamp);
        }
    }

    function getTotalSubsidyPool() external view returns (uint256) {
        return totalSubsidyPool;
    }

    function getTotalSubsidiesRemaining() external view returns (uint256) {
        return totalSubsidiesRemaining;
    }

    function getTotalEligibleUsers() external view returns (uint256) {
        return totalEligibleUsers;
    }

    function isUserEligible(address user) external view returns (bool) {
        return eligibleUsers[user];
    }

    function userSecondsClaimed(address user) external view returns (uint256) {
        if (user == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        return _userTotalSecondsClaimed[user];
    }
}
