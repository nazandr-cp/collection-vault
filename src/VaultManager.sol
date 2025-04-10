// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVault} from "./interfaces/IVault.sol";
import {INFTRegistry} from "./interfaces/INFTRegistry.sol";

/**
 * @title VaultManager
 * @notice Manages multiple yield-generating vaults associated with NFT collections.
 * @dev Acts as a central coordinator for claiming yield across different vaults and collections.
 *      Implements both global (`claimAll`) and collection-specific (`claimForCollection`) claims.
 *      Relies on an external NFT Registry to determine user NFT holdings.
 */
contract VaultManager is Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    // --- State Variables ---

    INFTRegistry public immutable nftRegistry;

    // Sets to keep track of registered vaults and collections
    EnumerableSet.AddressSet private _registeredVaults;
    EnumerableSet.AddressSet private _registeredCollections;

    // --- Structs ---

    /**
     * @notice Structure to hold details for each collection's claim within a global claim.
     * @param collection The address of the NFT collection.
     * @param yieldToken The address of the yield token distributed for this claim part.
     * @param amount The amount of yield token claimed for this specific collection/vault pair.
     */
    struct CollectionClaimData {
        address collection;
        address yieldToken;
        uint256 amount;
    }

    // --- Events ---

    /**
     * @notice Emitted when a user performs a global claim across all registered vaults and collections.
     * @param user The user who initiated the claim.
     * @param totalYieldTokens An array of unique yield token addresses claimed.
     * @param totalAmounts An array of corresponding total amounts claimed for each token.
     * @param timestamp The block timestamp of the claim.
     * @param blockNumber The block number of the claim.
     * @param details An array containing detailed breakdown per collection/vault.
     */
    event GlobalClaim(
        address indexed user,
        address[] totalYieldTokens,
        uint256[] totalAmounts,
        uint256 timestamp,
        uint256 blockNumber,
        CollectionClaimData[] details
    );

    /**
     * @notice Emitted when a user claims yield for a specific NFT collection.
     * @param user The user who initiated the claim.
     * @param collection The specific NFT collection for which yield was claimed.
     * @param yieldTokens An array of unique yield token addresses claimed from associated vaults.
     * @param amounts An array of corresponding amounts claimed for each token.
     * @param timestamp The block timestamp of the claim.
     * @param blockNumber The block number of the claim.
     */
    event CollectionClaim(
        address indexed user,
        address indexed collection,
        address[] yieldTokens,
        uint256[] amounts,
        uint256 timestamp,
        uint256 blockNumber
    );

    event VaultRegistered(address indexed vaultAddress);
    event VaultRemoved(address indexed vaultAddress);
    event CollectionRegistered(address indexed collectionAddress);
    event CollectionRemoved(address indexed collectionAddress);

    // --- Errors ---
    error CollectionNotRegistered(address collectionAddress);
    error VaultNotRegistered(address vaultAddress);
    error AddressZero();
    error NoYieldToClaim();
    error ClaimFailed(address vaultAddress, address user, uint256 amount);
    error ArrayLengthMismatch();

    // --- Constructor ---

    constructor(address initialOwner, address _nftRegistryAddress) Ownable(initialOwner) {
        if (_nftRegistryAddress == address(0)) revert AddressZero();
        nftRegistry = INFTRegistry(_nftRegistryAddress);
    }

    // --- Admin Functions (Manage Vaults and Collections) ---

    /**
     * @notice Registers a new token vault contract.
     * @dev Only callable by the owner.
     * @param vaultAddress The address of the vault contract conforming to IVault.
     */
    function addVault(address vaultAddress) external onlyOwner {
        if (vaultAddress == address(0)) revert AddressZero();
        // Optional: Add a check to ensure it conforms to IVault interface?
        // require(IVault(vaultAddress).supportsInterface(bytes4(keccak256("getYieldToken()"))), "VaultManager: Invalid vault interface");
        require(_registeredVaults.add(vaultAddress), "VaultManager: Vault already registered");
        emit VaultRegistered(vaultAddress);
    }

    /**
     * @notice Removes a registered token vault contract.
     * @dev Only callable by the owner.
     * @param vaultAddress The address of the vault contract to remove.
     */
    function removeVault(address vaultAddress) external onlyOwner {
        if (!_registeredVaults.remove(vaultAddress)) revert VaultNotRegistered(vaultAddress);
        emit VaultRemoved(vaultAddress);
    }

    /**
     * @notice Registers a new NFT collection contract.
     * @dev Only callable by the owner.
     * @param collectionAddress The address of the NFT collection contract.
     */
    function addCollection(address collectionAddress) external onlyOwner {
        if (collectionAddress == address(0)) revert AddressZero();
        require(_registeredCollections.add(collectionAddress), "VaultManager: Collection already registered");
        emit CollectionRegistered(collectionAddress);
    }

    /**
     * @notice Removes a registered NFT collection contract.
     * @dev Only callable by the owner.
     * @param collectionAddress The address of the NFT collection contract to remove.
     */
    function removeCollection(address collectionAddress) external onlyOwner {
        if (!_registeredCollections.remove(collectionAddress)) revert CollectionNotRegistered(collectionAddress);
        emit CollectionRemoved(collectionAddress);
    }

    // --- Claim Functions ---

    /**
     * @notice Claims yield for a specific NFT collection from all registered vaults.
     * @param collectionAddress The address of the NFT collection to claim yield for.
     */
    function claimForCollection(address collectionAddress) external nonReentrant {
        if (!isCollectionRegistered(collectionAddress)) {
            revert CollectionNotRegistered(collectionAddress);
        }

        address user = msg.sender;
        uint256 nftCount = nftRegistry.balanceOf(user, collectionAddress);

        if (nftCount == 0) {
            // Optionally revert, or just do nothing if the user holds no NFTs in this collection
            revert NoYieldToClaim();
        }

        uint256 vaultCount = _registeredVaults.length();
        if (vaultCount == 0) {
            // No vaults registered, nothing to claim
            revert NoYieldToClaim();
        }

        // Use temporary storage to aggregate claims per token
        mapping(address => uint256) tokenAmounts;
        address[] memory yieldTokens;
        uint256 tokenIndex = 0;

        for (uint256 i = 0; i < vaultCount; ++i) {
            address vaultAddr = _registeredVaults.at(i);
            IVault vault = IVault(vaultAddr);
            uint256 pendingYield = vault.getPendingYield(user, collectionAddress, nftCount);

            if (pendingYield > 0) {
                address yieldToken = address(vault.getYieldToken());
                if (tokenAmounts[yieldToken] == 0 && yieldToken != address(0)) {
                    // Add new token to the list (dynamically sized array is tricky, could preallocate max size)
                    // Using a temporary dynamic array approach here
                    address[] memory newYieldTokens = new address[](tokenIndex + 1);
                    for (uint256 j = 0; j < tokenIndex; ++j) {
                        newYieldTokens[j] = yieldTokens[j];
                    }
                    newYieldTokens[tokenIndex] = yieldToken;
                    yieldTokens = newYieldTokens;
                    tokenIndex++;
                }
                tokenAmounts[yieldToken] += pendingYield;

                // Execute the distribution
                bool success = vault.distributeYield(user, pendingYield);
                if (!success) {
                    revert ClaimFailed(vaultAddr, user, pendingYield);
                }
            }
        }

        if (tokenIndex == 0) {
            // No actual yield was > 0 across all vaults for this collection
            revert NoYieldToClaim();
        }

        // Prepare amounts array matching the order of yieldTokens
        uint256[] memory amounts = new uint256[](tokenIndex);
        for (uint256 k = 0; k < tokenIndex; ++k) {
            amounts[k] = tokenAmounts[yieldTokens[k]];
        }

        emit CollectionClaim(user, collectionAddress, yieldTokens, amounts, block.timestamp, block.number);
    }

    /**
     * @notice Claims yield from all registered vaults across all registered NFT collections
     *         for which the user holds NFTs.
     */
    function claimAll() external nonReentrant {
        address user = msg.sender;
        uint256 collectionCount = _registeredCollections.length();
        uint256 vaultCount = _registeredVaults.length();

        if (collectionCount == 0 || vaultCount == 0) {
            revert NoYieldToClaim(); // Nothing to claim if no collections or vaults
        }

        // Temporary storage for aggregation
        mapping(address => uint256) totalTokenAmounts; // yieldToken => totalAmount
        address[] memory yieldTokens; // List of unique yield tokens encountered
        uint256 tokenIndex = 0;
        CollectionClaimData[] memory claimDetails = new CollectionClaimData[](collectionCount * vaultCount); // Max possible size
        uint256 detailIndex = 0;

        for (uint256 i = 0; i < collectionCount; ++i) {
            address collectionAddr = _registeredCollections.at(i);
            uint256 nftCount = nftRegistry.balanceOf(user, collectionAddr);

            if (nftCount > 0) {
                for (uint256 j = 0; j < vaultCount; ++j) {
                    address vaultAddr = _registeredVaults.at(j);
                    IVault vault = IVault(vaultAddr);
                    uint256 pendingYield = vault.getPendingYield(user, collectionAddr, nftCount);

                    if (pendingYield > 0) {
                        address yieldToken = address(vault.getYieldToken());
                        if (yieldToken == address(0)) continue; // Skip if vault returns zero address token

                        // Track unique tokens
                        if (totalTokenAmounts[yieldToken] == 0) {
                            address[] memory newYieldTokens = new address[](tokenIndex + 1);
                            for (uint256 k = 0; k < tokenIndex; ++k) {
                                newYieldTokens[k] = yieldTokens[k];
                            }
                            newYieldTokens[tokenIndex] = yieldToken;
                            yieldTokens = newYieldTokens;
                            tokenIndex++;
                        }
                        totalTokenAmounts[yieldToken] += pendingYield;

                        // Record detail
                        claimDetails[detailIndex++] = CollectionClaimData({
                            collection: collectionAddr,
                            yieldToken: yieldToken,
                            amount: pendingYield
                        });

                        // Execute distribution
                        bool success = vault.distributeYield(user, pendingYield);
                        if (!success) {
                            revert ClaimFailed(vaultAddr, user, pendingYield);
                        }
                    }
                }
            }
        }

        if (detailIndex == 0) {
            // User held NFTs, but no vault yielded > 0 for those NFTs
            revert NoYieldToClaim();
        }

        // Prepare final aggregated amounts array
        uint256[] memory totalAmounts = new uint256[](tokenIndex);
        for (uint256 k = 0; k < tokenIndex; ++k) {
            totalAmounts[k] = totalTokenAmounts[yieldTokens[k]];
        }

        // Resize details array to actual count
        CollectionClaimData[] memory finalDetails = new CollectionClaimData[](detailIndex);
        for (uint256 k = 0; k < detailIndex; ++k) {
            finalDetails[k] = claimDetails[k];
        }

        emit GlobalClaim(user, yieldTokens, totalAmounts, block.timestamp, block.number, finalDetails);
    }

    // --- View Functions ---

    /**
     * @notice Checks if a vault address is registered.
     * @param vaultAddress The address to check.
     * @return True if registered, false otherwise.
     */
    function isVaultRegistered(address vaultAddress) public view returns (bool) {
        return _registeredVaults.contains(vaultAddress);
    }

    /**
     * @notice Checks if a collection address is registered.
     * @param collectionAddress The address to check.
     * @return True if registered, false otherwise.
     */
    function isCollectionRegistered(address collectionAddress) public view returns (bool) {
        return _registeredCollections.contains(collectionAddress);
    }

    /**
     * @notice Returns an array of all registered vault addresses.
     */
    function getRegisteredVaults() public view returns (address[] memory) {
        return _registeredVaults.values();
    }

    /**
     * @notice Returns an array of all registered collection addresses.
     */
    function getRegisteredCollections() public view returns (address[] memory) {
        return _registeredCollections.values();
    }

    /**
     * @notice Calculates the total pending yield for a specific user across all registered collections and vaults.
     * @dev This is a view function and does not execute claims.
     *      It returns aggregated amounts per yield token.
     * @param user The address of the user.
     * @return yieldTokens_ Array of unique yield token addresses with pending yield.
     * @return amounts_ Array of corresponding total pending amounts for each token.
     */
    function getTotalPendingYield(address user)
        public
        view
        returns (address[] memory yieldTokens_, uint256[] memory amounts_)
    {
        uint256 collectionCount = _registeredCollections.length();
        uint256 vaultCount = _registeredVaults.length();

        if (collectionCount == 0 || vaultCount == 0) {
            return (new address[](0), new uint256[](0));
        }

        mapping(address => uint256) tokenAmounts;
        address[] memory yieldTokens; // Temporary list of unique tokens
        uint256 tokenIndex = 0;

        for (uint256 i = 0; i < collectionCount; ++i) {
            address collectionAddr = _registeredCollections.at(i);
            uint256 nftCount = nftRegistry.balanceOf(user, collectionAddr);

            if (nftCount > 0) {
                for (uint256 j = 0; j < vaultCount; ++j) {
                    address vaultAddr = _registeredVaults.at(j);
                    IVault vault = IVault(vaultAddr);
                    uint256 pendingYield = vault.getPendingYield(user, collectionAddr, nftCount);

                    if (pendingYield > 0) {
                        address yieldToken = address(vault.getYieldToken());
                        if (yieldToken == address(0)) continue;

                        if (tokenAmounts[yieldToken] == 0) {
                            // Add new token to the list
                            address[] memory newYieldTokens = new address[](tokenIndex + 1);
                            for (uint256 k = 0; k < tokenIndex; ++k) {
                                newYieldTokens[k] = yieldTokens[k];
                            }
                            newYieldTokens[tokenIndex] = yieldToken;
                            yieldTokens = newYieldTokens;
                            tokenIndex++;
                        }
                        tokenAmounts[yieldToken] += pendingYield;
                    }
                }
            }
        }

        // Prepare final arrays
        yieldTokens_ = yieldTokens; // Assign the dynamically built array
        amounts_ = new uint256[](tokenIndex);
        for (uint256 k = 0; k < tokenIndex; ++k) {
            amounts_[k] = tokenAmounts[yieldTokens_[k]];
        }

        return (yieldTokens_, amounts_);
    }

    /**
     * @notice Calculates the pending yield for a specific user and a specific collection across all registered vaults.
     * @dev This is a view function and does not execute claims.
     *      It returns aggregated amounts per yield token for that single collection.
     * @param user The address of the user.
     * @param collectionAddress The address of the specific NFT collection.
     * @return yieldTokens_ Array of unique yield token addresses with pending yield for this collection.
     * @return amounts_ Array of corresponding pending amounts for each token.
     */
    function getPendingYieldForCollection(address user, address collectionAddress)
        public
        view
        returns (address[] memory yieldTokens_, uint256[] memory amounts_)
    {
        if (!isCollectionRegistered(collectionAddress)) {
            // Or return empty arrays? Reverting might be clearer.
            revert CollectionNotRegistered(collectionAddress);
        }

        uint256 nftCount = nftRegistry.balanceOf(user, collectionAddress);
        uint256 vaultCount = _registeredVaults.length();

        if (nftCount == 0 || vaultCount == 0) {
            return (new address[](0), new uint256[](0));
        }

        mapping(address => uint256) tokenAmounts;
        address[] memory yieldTokens; // Temporary list of unique tokens
        uint256 tokenIndex = 0;

        for (uint256 j = 0; j < vaultCount; ++j) {
            address vaultAddr = _registeredVaults.at(j);
            IVault vault = IVault(vaultAddr);
            uint256 pendingYield = vault.getPendingYield(user, collectionAddress, nftCount);

            if (pendingYield > 0) {
                address yieldToken = address(vault.getYieldToken());
                if (yieldToken == address(0)) continue;

                if (tokenAmounts[yieldToken] == 0) {
                    // Add new token to the list
                    address[] memory newYieldTokens = new address[](tokenIndex + 1);
                    for (uint256 k = 0; k < tokenIndex; ++k) {
                        newYieldTokens[k] = yieldTokens[k];
                    }
                    newYieldTokens[tokenIndex] = yieldToken;
                    yieldTokens = newYieldTokens;
                    tokenIndex++;
                }
                tokenAmounts[yieldToken] += pendingYield;
            }
        }

        // Prepare final arrays
        yieldTokens_ = yieldTokens;
        amounts_ = new uint256[](tokenIndex);
        for (uint256 k = 0; k < tokenIndex; ++k) {
            amounts_[k] = tokenAmounts[yieldTokens_[k]];
        }

        return (yieldTokens_, amounts_);
    }
}
