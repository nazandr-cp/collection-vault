// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlBaseUpgradeable} from "./AccessControlBaseUpgradeable.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {Roles} from "./Roles.sol";

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

contract DebtSubsidizer is Initializable, IDebtSubsidizer, AccessControlBaseUpgradeable {
    using SafeERC20 for IERC20;
    using ERC165Checker for address;

    struct InternalVaultInfo {
        address cToken;
    }

    uint16 private constant MAX_YIELD_SHARE_PERCENTAGE = 10000;
    uint16 private constant MIN_YIELD_SHARE_PERCENTAGE = 100;
    uint256 private constant MAX_BATCH_SIZE = 50;

    mapping(address => InternalVaultInfo) internal _vaultsData;
    mapping(address => bytes32) internal _merkleRoots; // Vault address => Merkle Root
    mapping(address => mapping(address => uint256)) internal _claimedTotals; // vault => user => total claimed
    mapping(address => uint256) internal _totalClaimedByVault; // vault => total claimed across all users

    mapping(address => mapping(address => bool)) internal _isCollectionWhitelisted;
    mapping(address => address[]) internal _vaultWhitelistedCollections; // vault => array of whitelisted collections
    mapping(address => mapping(address => uint256)) internal _userSecondsClaimed;
    mapping(address => uint256) internal _userTotalSecondsClaimed;
    ICollectionRegistry public collectionRegistry;

    mapping(address => uint256) public totalSubsidies; // vault => total allocated subsidies
    mapping(address => uint256) public totalSubsidiesClaimed; // vault => total claimed subsidies

    mapping(address => bool) internal _vaultRemoved;
    mapping(address => mapping(address => bool)) internal _collectionRemoved;
    mapping(address => bool) internal _vaultHasDeposits;

    mapping(bytes32 => uint256) internal _circuitBreakerFailures;
    mapping(bytes32 => uint256) internal _circuitBreakerLastFailure;
    mapping(address => mapping(bytes4 => uint256)) internal _rateLimitCounts;
    mapping(address => mapping(bytes4 => uint256)) internal _rateLimitWindows;

    event VaultDeactivated(address indexed vault);
    event CollectionDeactivated(address indexed vault, address indexed collection);

    constructor() {
        _disableInitializers();
    }

    function initialize(address initialAdmin, address registry) public initializer {
        if (initialAdmin == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (registry == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        __AccessControlBase_init(initialAdmin);
        collectionRegistry = ICollectionRegistry(registry);
    }

    function addVault(address vaultAddress_, address lendingManagerAddress_)
        external
        override(IDebtSubsidizer)
        onlyRole(Roles.ADMIN_ROLE)
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
        _vaultRemoved[vaultAddress_] = false;

        emit VaultAdded(vaultAddress_, cTokenAddress, lendingManagerAddress_);
    }

    function removeVault(address vaultAddress_) external override(IDebtSubsidizer) onlyRole(Roles.ADMIN_ROLE) {
        if (vaultAddress_ == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (_vaultsData[vaultAddress_].cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress_);
        }

        if (_vaultHasDeposits[vaultAddress_]) {
            _vaultRemoved[vaultAddress_] = true;
            emit VaultDeactivated(vaultAddress_);
            return;
        }

        address[] memory whitelistedCollections = _vaultWhitelistedCollections[vaultAddress_];
        for (uint256 i = 0; i < whitelistedCollections.length; i++) {
            delete _isCollectionWhitelisted[vaultAddress_][whitelistedCollections[i]];
            delete _collectionRemoved[vaultAddress_][whitelistedCollections[i]];
        }
        delete _vaultWhitelistedCollections[vaultAddress_];

        delete _vaultsData[vaultAddress_];
        delete _vaultRemoved[vaultAddress_];

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
        onlyRole(Roles.ADMIN_ROLE)
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
        onlyRole(Roles.ADMIN_ROLE)
    {
        if (vaultAddress == address(0) || collectionAddress == address(0)) revert IDebtSubsidizer.AddressZero();
        if (!_isCollectionWhitelisted[vaultAddress][collectionAddress]) {
            revert IDebtSubsidizer.CollectionNotWhitelistedInVault(vaultAddress, collectionAddress);
        }
        if (_vaultHasDeposits[vaultAddress]) {
            _collectionRemoved[vaultAddress][collectionAddress] = true;
            emit CollectionDeactivated(vaultAddress, collectionAddress);
            return;
        }

        delete _isCollectionWhitelisted[vaultAddress][collectionAddress];

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
        _totalClaimedByVault[vaultAddress] += amountToSubsidize;

        if (amountToSubsidize > 0) {
            _vaultHasDeposits[vaultAddress] = true;

            // Check if there are sufficient allocated subsidies for this vault
            if (totalSubsidiesClaimed[vaultAddress] + amountToSubsidize > totalSubsidies[vaultAddress]) {
                revert IDebtSubsidizer.InsufficientYield();
            }

            // Update claimed amounts
            totalSubsidiesClaimed[vaultAddress] += amountToSubsidize;
            _userTotalSecondsClaimed[recipient] += amountToSubsidize;

            emit SubsidyClaimed(vaultAddress, recipient, amountToSubsidize);

            bytes32 circuitId = keccak256(abi.encodePacked("vault.repayBorrowBehalf", vaultAddress));
            _checkCircuitBreaker(circuitId);

            try ICollectionsVault(vaultAddress).repayBorrowBehalf(amountToSubsidize, recipient) {
                _circuitBreakerFailures[circuitId] = 0;
            } catch {
                _recordVaultFailure(circuitId);
                revert IDebtSubsidizer.InsufficientYield();
            }
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
        if (len > MAX_BATCH_SIZE) {
            revert("DebtSubsidizer: Batch size exceeds maximum limit");
        }
        for (uint256 i = 0; i < len;) {
            _claimSubsidy(vaultAddresses[i], claims[i]);
            unchecked {
                ++i;
            }
        }
    }

    function updateMerkleRoot(address vaultAddress, bytes32 merkleRoot_, uint256 totalSubsidiesForEpoch)
        external
        override(IDebtSubsidizer)
        onlyRole(Roles.ADMIN_ROLE)
    {
        if (vaultAddress == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        if (_vaultsData[vaultAddress].cToken == address(0)) {
            revert IDebtSubsidizer.VaultNotRegistered(vaultAddress);
        }
        _merkleRoots[vaultAddress] = merkleRoot_;
        totalSubsidies[vaultAddress] += totalSubsidiesForEpoch;
        emit MerkleRootUpdated(vaultAddress, merkleRoot_, msg.sender, totalSubsidiesForEpoch);
    }

    function getMerkleRoot(address vaultAddress) external view returns (bytes32) {
        return _merkleRoots[vaultAddress];
    }

    function getTotalClaimedForVault(address vaultAddress) external view returns (uint256) {
        return _totalClaimedByVault[vaultAddress];
    }

    function getUserClaimedTotal(address vaultAddress, address user) external view returns (uint256) {
        return _claimedTotals[vaultAddress][user];
    }

    function validateVaultClaimsIntegrity(address vaultAddress)
        external
        view
        returns (bool isValid, uint256 totalClaimed, uint256 totalAllocated)
    {
        totalClaimed = _totalClaimedByVault[vaultAddress];

        try ICollectionsVault(vaultAddress).totalYieldAllocatedCumulative() returns (uint256 allocated) {
            totalAllocated = allocated;
            isValid = totalClaimed <= totalAllocated;
        } catch {
            totalAllocated = 0;
            isValid = false;
        }
    }

    function emergencyValidateAndPause(address vaultAddress) external onlyRole(Roles.ADMIN_ROLE) {
        (bool isValid, uint256 totalClaimed, uint256 totalAllocated) = this.validateVaultClaimsIntegrity(vaultAddress);

        if (!isValid) {
            _pause();
            emit MerkleRootUpdated(
                vaultAddress,
                bytes32(0), // Clear merkle root to prevent further claims
                msg.sender,
                0 // No subsidies for emergency clear
            );
        }
    }

    function isCollectionWhitelisted(address vaultAddress, address collectionAddress)
        external
        view
        override(IDebtSubsidizer)
        returns (bool)
    {
        return _isCollectionWhitelisted[vaultAddress][collectionAddress]
            && !_collectionRemoved[vaultAddress][collectionAddress];
    }

    function paused() public view override(IDebtSubsidizer, PausableUpgradeable) returns (bool) {
        return super.paused();
    }

    function getTotalSubsidies(address vaultAddress) external view returns (uint256) {
        return totalSubsidies[vaultAddress];
    }

    function getTotalSubsidiesClaimed(address vaultAddress) external view returns (uint256) {
        return totalSubsidiesClaimed[vaultAddress];
    }

    function getRemainingSubsidies(address vaultAddress) external view returns (uint256) {
        return totalSubsidies[vaultAddress] - totalSubsidiesClaimed[vaultAddress];
    }

    function isVaultRemoved(address vaultAddress) external view returns (bool) {
        return _vaultRemoved[vaultAddress];
    }

    function isCollectionRemoved(address vaultAddress, address collection) external view returns (bool) {
        return _collectionRemoved[vaultAddress][collection];
    }

    function userSecondsClaimed(address user) external view returns (uint256) {
        if (user == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        return _userTotalSecondsClaimed[user];
    }

    function setCollectionRegistry(address newRegistry) external onlyRole(Roles.ADMIN_ROLE) {
        if (newRegistry == address(0)) {
            revert IDebtSubsidizer.AddressZero();
        }
        address oldRegistry = address(collectionRegistry);
        collectionRegistry = ICollectionRegistry(newRegistry);
        emit CollectionRegistryUpdated(oldRegistry, newRegistry);
    }

    function _checkCircuitBreaker(bytes32 circuitId) internal view {
        uint256 failures = _circuitBreakerFailures[circuitId];
        uint256 lastFailure = _circuitBreakerLastFailure[circuitId];

        if (failures >= 5 && block.timestamp < lastFailure + 300) {
            revert IDebtSubsidizer.InsufficientYield();
        }
    }

    function _recordVaultFailure(bytes32 circuitId) internal {
        _circuitBreakerFailures[circuitId]++;
        _circuitBreakerLastFailure[circuitId] = block.timestamp;

        if (block.timestamp >= _circuitBreakerLastFailure[circuitId] + 300) {
            _circuitBreakerFailures[circuitId] = 1;
        }
    }

    function resetCircuitBreaker(bytes32 circuitId) external onlyRole(Roles.GUARDIAN_ROLE) {
        _circuitBreakerFailures[circuitId] = 0;
        _circuitBreakerLastFailure[circuitId] = 0;
    }
}
