// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {RewardsController} from "../../src/RewardsController.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract RewardsController_Admin_Test is RewardsController_Test_Base {
    address internal constant NEW_UPDATER = address(0x4);
    address internal constant OTHER_ADDRESS = address(0x5);

    function setUp() public virtual override {
        super.setUp();
        // Deploy a new implementation for re-initialization tests
        rewardsControllerImplementation = address(new RewardsController());
        // Set the mockLendingManager and mockCollectionsVault to point to the setup instances
        mockLendingManager = address(lendingManager);
        mockCollectionsVault = address(tokenVault);
    }

    // --- Test Deployment and initialize() ---

    function test_Initialize_CorrectDeploymentAndInitialization() public {
        assertTrue(address(rewardsController) != address(0), "Proxy not deployed");
        assertTrue(rewardsControllerImplementation != address(0), "Implementation not deployed");
        // Initialized event is checked in the base setup, here we check if it's callable
        // and that basic setup values are present (owner is a good proxy for this)
        assertEq(rewardsController.owner(), ADMIN, "Owner not admin after init");
    }

    function test_Initialize_SetsCorrectInitialValues() public {
        assertEq(rewardsController.owner(), ADMIN, "Initial owner incorrect");
        assertEq(
            address(rewardsController.lendingManager()), address(mockLendingManager), "Initial lendingManager incorrect"
        );
        assertEq(address(rewardsController.vault()), address(mockCollectionsVault), "Initial tokenVault incorrect");
        assertEq(rewardsController.trustedSigner(), UPDATER, "Initial authorizedUpdater incorrect");
    }

    function test_Initialize_RevertsIfCalledTwiceOnImplementation() public {
        RewardsController implementation = RewardsController(payable(rewardsControllerImplementation));
        // First call (simulating proxy's call)
        implementation.initialize(ADMIN, address(mockLendingManager), address(mockCollectionsVault), UPDATER);

        // Second call should revert
        vm.expectRevert(RewardsController.InvalidInitialization.selector);
        implementation.initialize(ADMIN, address(mockLendingManager), address(mockCollectionsVault), UPDATER);
    }

    function test_Initialize_RevertsIfCalledOnProxyAfterSetup() public {
        vm.expectRevert(RewardsController.InvalidInitialization.selector);
        rewardsController.initialize(
            USER_1, // Try to reinitialize with different owner
            address(mockLendingManager),
            address(mockCollectionsVault),
            USER_1
        );
    }

    // --- Test Ownership and Admin Roles ---

    function test_Owner_ReturnsCorrectOwner() public {
        assertEq(rewardsController.owner(), ADMIN, "Owner mismatch");
    }

    function test_TransferOwnership_Successful() public {
        vm.prank(ADMIN);
        rewardsController.transferOwnership(USER_1);
        assertEq(rewardsController.owner(), USER_1, "Ownership not transferred");
    }

    function test_TransferOwnership_RevertsIfNonOwner() public {
        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.transferOwnership(USER_2);
    }

    function test_TransferOwnership_RevertsIfNewOwnerIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableInvalidOwner.selector, address(0)));
        rewardsController.transferOwnership(address(0));
    }

    function test_TransferOwnership_EmitsEvent() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(ADMIN, USER_1);
        rewardsController.transferOwnership(USER_1);
    }

    function test_RenounceOwnership_Successful() public {
        vm.prank(ADMIN);
        rewardsController.renounceOwnership();
        assertEq(rewardsController.owner(), address(0), "Ownership not renounced");
    }

    function test_RenounceOwnership_RevertsIfNonOwner() public {
        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.renounceOwnership();
    }

    function test_RenounceOwnership_EmitsEvent() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit OwnershipTransferred(ADMIN, address(0));
        rewardsController.renounceOwnership();
    }

    function test_RenounceOwnership_SetsOwnerToAddressZero() public {
        vm.prank(ADMIN);
        rewardsController.renounceOwnership();
        assertEq(rewardsController.owner(), address(0), "Owner not address(0)");
    }

    // --- Test Core Contract Addresses ---

    // These tests are commented out as the setLendingManager functionality is not implemented in the contract
    /*
    function test_SetLendingManager_Successful() public {
        address newLendingManager = address(0x1234);
        
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit LendingManagerUpdated(address(mockLendingManager), newLendingManager);
        rewardsController.setLendingManager(newLendingManager);
        
        assertEq(address(rewardsController.lendingManager()), newLendingManager, "LendingManager not updated");
    }
    
    function test_SetLendingManager_RevertIfNonOwner() public {
        address newLendingManager = address(0x1234);
        
        vm.prank(USER_1); // Non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        rewardsController.setLendingManager(newLendingManager);
    }
    
    function test_SetLendingManager_RevertIfAddressZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setLendingManager(address(0));
    }
    */

    // These tests are commented out as the setTokenVault functionality is not implemented in the contract
    /*
    function test_SetTokenVault_Successful() public {
        address newTokenVault = address(0x5678);
        
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit TokenVaultUpdated(address(mockCollectionsVault), newTokenVault);
        rewardsController.setTokenVault(newTokenVault);
        
        assertEq(address(rewardsController.vault()), newTokenVault, "TokenVault not updated");
    }
    
    function test_SetTokenVault_RevertIfNonOwner() public {
        address newTokenVault = address(0x5678);
        
        vm.prank(USER_1); // Non-owner
        vm.expectRevert("Ownable: caller is not the owner");
        rewardsController.setTokenVault(newTokenVault);
    }
    
    function test_SetTokenVault_RevertIfAddressZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setTokenVault(address(0));
    }
    */

    // --- Test Managing NFT Collections ---

    function test_AddNFTCollection_Successful() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionAdded(newCollection, beta, rewardBasis, rewardSharePercentage);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);

        assertTrue(rewardsController.isCollectionWhitelisted(newCollection), "Collection not whitelisted");

        (uint256 configBeta, IRewardsController.RewardBasis configBasis, uint256 configShare) =
            rewardsController.getCollectionData(newCollection);
        assertEq(configBeta, beta, "Beta value incorrect");
        assertEq(uint8(configBasis), uint8(rewardBasis), "RewardBasis incorrect");
        assertEq(configShare, rewardSharePercentage, "RewardSharePercentage incorrect");
    }

    function test_AddNFTCollection_RevertIfNonOwner() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfAddressZero() public {
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.addNFTCollection(address(0), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfCollectionAlreadyExists() public {
        // mockERC721 is already added in the base setup
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(IRewardsController.CollectionAlreadyExists.selector, address(mockERC721))
        );
        rewardsController.addNFTCollection(address(mockERC721), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfInvalidRewardSharePercentage() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, invalidSharePercentage);
    }

    function test_UpdateBeta_Successful() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value
        uint256 oldBeta = BETA_1;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit BetaUpdated(collection, oldBeta, newBeta);
        rewardsController.updateBeta(collection, newBeta);

        (uint256 configBeta,,) = rewardsController.getCollectionData(collection);
        assertEq(configBeta, newBeta, "Beta value not updated");
    }

    function test_UpdateBeta_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_UpdateBeta_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_SetCollectionRewardSharePercentage_Successful() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;
        uint256 oldSharePercentage = VALID_REWARD_SHARE_PERCENTAGE;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);

        (,, uint256 configShare) = rewardsController.getCollectionData(collection);
        assertEq(configShare, newSharePercentage, "RewardSharePercentage not updated");
    }

    function test_SetCollectionRewardSharePercentage_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newSharePercentage = 7500;

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfInvalidSharePercentage() public {
        address collection = address(mockERC721);
        uint256 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setCollectionRewardSharePercentage(collection, invalidSharePercentage);
    }

    function test_RemoveNFTCollection_Successful() public {
        address collection = address(mockERC721);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionRemoved(collection);
        rewardsController.removeNFTCollection(collection);

        assertFalse(rewardsController.isCollectionWhitelisted(collection), "Collection still whitelisted");

        // Trying to access data for a removed collection should revert
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.getCollectionData(collection);
    }

    function test_RemoveNFTCollection_RevertIfNonOwner() public {
        address collection = address(mockERC721);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.removeNFTCollection(collection);
    }

    function test_RemoveNFTCollection_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.removeNFTCollection(collection);
    }

    // --- Test Managing authorizedUpdater ---

    function test_SetTrustedSigner_Successful() public {
        address newUpdater = address(0x9999);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit TrustedSignerUpdated(UPDATER, newUpdater, ADMIN);
        rewardsController.setTrustedSigner(newUpdater);

        assertEq(rewardsController.trustedSigner(), newUpdater, "TrustedSigner not updated");
    }

    function test_SetTrustedSigner_RevertIfNonOwner() public {
        address newUpdater = address(0x9999);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setTrustedSigner(newUpdater);
    }

    function test_SetTrustedSigner_RevertIfAddressZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setTrustedSigner(address(0));
    }

    // Commenting out this test as authorizedUpdaterNonce is not part of the current interface
    /*
    function test_GetAuthorizedUpdaterNonce() public {
        // Initially it should be 0
        assertEq(rewardsController.authorizedUpdaterNonce(), 0, "Initial nonce incorrect");
        
        // After updating, it should increment
        address newUpdater = address(0x9999);
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(newUpdater);
        assertEq(rewardsController.authorizedUpdaterNonce(), 1, "Nonce not incremented after update");
        
        // Update again to check further incrementation
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(address(0x8888));
        assertEq(rewardsController.authorizedUpdaterNonce(), 2, "Nonce not incremented after second update");
    }
    */

    // --- Test Managing maxRewardSharePercentage ---

    function test_SetMaxRewardSharePercentage_Successful() public {
        uint16 newMaxRewardShare = 8000;
        uint16 oldMaxRewardShare = rewardsController.maxRewardSharePercentage();

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit MaxRewardSharePercentageUpdated(oldMaxRewardShare, newMaxRewardShare);
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);

        assertEq(
            rewardsController.maxRewardSharePercentage(), newMaxRewardShare, "MaxRewardSharePercentage not updated"
        );
    }

    function test_SetMaxRewardSharePercentage_RevertIfNonOwner() public {
        uint16 newMaxRewardShare = 8000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfZero() public {
        uint16 zeroRewardShare = 0;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(zeroRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfExceedsMaximumLimit() public {
        uint16 tooHighRewardShare = 10001; // > MAX_REWARD_SHARE_PERCENTAGE_LIMIT (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(tooHighRewardShare);
    }

    function test_SetMaxRewardSharePercentage_AllowsLowerThanExistingCollections() public {
        // This test verifies that setting a lower max doesn't affect existing collections
        uint16 lowerMaxRewardShare = 4000; // Lower than VALID_REWARD_SHARE_PERCENTAGE (5000)

        vm.prank(ADMIN);
        rewardsController.setMaxRewardSharePercentage(lowerMaxRewardShare);

        // Check existing collection still has its original percentage
        (,, uint256 configShare) = rewardsController.getCollectionData(address(mockERC721));
        assertEq(configShare, VALID_REWARD_SHARE_PERCENTAGE, "Existing collection reward share was modified");

        // But adding new collection with higher percentage should fail
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, VALID_REWARD_SHARE_PERCENTAGE);

        // Adding with lower percentage should work
        vm.prank(ADMIN);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, lowerMaxRewardShare);
        assertTrue(
            rewardsController.isCollectionWhitelisted(newCollection), "Collection not added with valid lower percentage"
        );
    }

    // --- Test Fuzzed Initialize ---

    function testFuzz_Initialize_RevertIfAlreadyInitialized(address randomAddress) public {
        vm.assume(randomAddress != address(0));
        vm.prank(ADMIN);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rewardsController.initialize(randomAddress, randomAddress, randomAddress, randomAddress);
    }

    // --- Test Managing Owner ---

    function test_SetOwner_RevertIfNotOwner() public {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setOwner(USER_1);
    }

    function test_SetOwner_RevertIfNewOwnerIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        rewardsController.setOwner(address(0));
    }

    function test_SetOwner_Success() public {
        vm.prank(ADMIN);
        rewardsController.setOwner(USER_1);
        assertEq(rewardsController.owner(), USER_1);
    }

    // --- Test Managing NFT Collections ---

    function test_AddNFTCollection_Successful() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionAdded(newCollection, beta, rewardBasis, rewardSharePercentage);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);

        assertTrue(rewardsController.isCollectionWhitelisted(newCollection), "Collection not whitelisted");

        (uint256 configBeta, IRewardsController.RewardBasis configBasis, uint256 configShare) =
            rewardsController.getCollectionData(newCollection);
        assertEq(configBeta, beta, "Beta value incorrect");
        assertEq(uint8(configBasis), uint8(rewardBasis), "RewardBasis incorrect");
        assertEq(configShare, rewardSharePercentage, "RewardSharePercentage incorrect");
    }

    function test_AddNFTCollection_RevertIfNonOwner() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfAddressZero() public {
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.addNFTCollection(address(0), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfCollectionAlreadyExists() public {
        // mockERC721 is already added in the base setup
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(IRewardsController.CollectionAlreadyExists.selector, address(mockERC721))
        );
        rewardsController.addNFTCollection(address(mockERC721), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfInvalidRewardSharePercentage() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, invalidSharePercentage);
    }

    function test_UpdateBeta_Successful() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value
        uint256 oldBeta = BETA_1;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit BetaUpdated(collection, oldBeta, newBeta);
        rewardsController.updateBeta(collection, newBeta);

        (uint256 configBeta,,) = rewardsController.getCollectionData(collection);
        assertEq(configBeta, newBeta, "Beta value not updated");
    }

    function test_UpdateBeta_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_UpdateBeta_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_SetCollectionRewardSharePercentage_Successful() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;
        uint256 oldSharePercentage = VALID_REWARD_SHARE_PERCENTAGE;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);

        (,, uint256 configShare) = rewardsController.getCollectionData(collection);
        assertEq(configShare, newSharePercentage, "RewardSharePercentage not updated");
    }

    function test_SetCollectionRewardSharePercentage_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newSharePercentage = 7500;

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfInvalidSharePercentage() public {
        address collection = address(mockERC721);
        uint256 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setCollectionRewardSharePercentage(collection, invalidSharePercentage);
    }

    function test_RemoveNFTCollection_Successful() public {
        address collection = address(mockERC721);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionRemoved(collection);
        rewardsController.removeNFTCollection(collection);

        assertFalse(rewardsController.isCollectionWhitelisted(collection), "Collection still whitelisted");

        // Trying to access data for a removed collection should revert
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.getCollectionData(collection);
    }

    function test_RemoveNFTCollection_RevertIfNonOwner() public {
        address collection = address(mockERC721);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.removeNFTCollection(collection);
    }

    function test_RemoveNFTCollection_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.removeNFTCollection(collection);
    }

    // --- Test Managing authorizedUpdater ---

    function test_SetTrustedSigner_Successful() public {
        address newUpdater = address(0x9999);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit TrustedSignerUpdated(UPDATER, newUpdater, ADMIN);
        rewardsController.setTrustedSigner(newUpdater);

        assertEq(rewardsController.trustedSigner(), newUpdater, "TrustedSigner not updated");
    }

    function test_SetTrustedSigner_RevertIfNonOwner() public {
        address newUpdater = address(0x9999);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setTrustedSigner(newUpdater);
    }

    function test_SetTrustedSigner_RevertIfAddressZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setTrustedSigner(address(0));
    }

    // Commenting out this test as authorizedUpdaterNonce is not part of the current interface
    /*
    function test_GetAuthorizedUpdaterNonce() public {
        // Initially it should be 0
        assertEq(rewardsController.authorizedUpdaterNonce(), 0, "Initial nonce incorrect");
        
        // After updating, it should increment
        address newUpdater = address(0x9999);
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(newUpdater);
        assertEq(rewardsController.authorizedUpdaterNonce(), 1, "Nonce not incremented after update");
        
        // Update again to check further incrementation
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(address(0x8888));
        assertEq(rewardsController.authorizedUpdaterNonce(), 2, "Nonce not incremented after second update");
    }
    */

    // --- Test Managing maxRewardSharePercentage ---

    function test_SetMaxRewardSharePercentage_Successful() public {
        uint16 newMaxRewardShare = 8000;
        uint16 oldMaxRewardShare = rewardsController.maxRewardSharePercentage();

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit MaxRewardSharePercentageUpdated(oldMaxRewardShare, newMaxRewardShare);
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);

        assertEq(
            rewardsController.maxRewardSharePercentage(), newMaxRewardShare, "MaxRewardSharePercentage not updated"
        );
    }

    function test_SetMaxRewardSharePercentage_RevertIfNonOwner() public {
        uint16 newMaxRewardShare = 8000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfZero() public {
        uint16 zeroRewardShare = 0;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(zeroRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfExceedsMaximumLimit() public {
        uint16 tooHighRewardShare = 10001; // > MAX_REWARD_SHARE_PERCENTAGE_LIMIT (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(tooHighRewardShare);
    }

    function test_SetMaxRewardSharePercentage_AllowsLowerThanExistingCollections() public {
        // This test verifies that setting a lower max doesn't affect existing collections
        uint16 lowerMaxRewardShare = 4000; // Lower than VALID_REWARD_SHARE_PERCENTAGE (5000)

        vm.prank(ADMIN);
        rewardsController.setMaxRewardSharePercentage(lowerMaxRewardShare);

        // Check existing collection still has its original percentage
        (,, uint256 configShare) = rewardsController.getCollectionData(address(mockERC721));
        assertEq(configShare, VALID_REWARD_SHARE_PERCENTAGE, "Existing collection reward share was modified");

        // But adding new collection with higher percentage should fail
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, VALID_REWARD_SHARE_PERCENTAGE);

        // Adding with lower percentage should work
        vm.prank(ADMIN);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, lowerMaxRewardShare);
        assertTrue(
            rewardsController.isCollectionWhitelisted(newCollection), "Collection not added with valid lower percentage"
        );
    }

    // --- Test Fuzzed Initialize ---

    function testFuzz_Initialize_RevertIfAlreadyInitialized(address randomAddress) public {
        vm.assume(randomAddress != address(0));
        vm.prank(ADMIN);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rewardsController.initialize(randomAddress, randomAddress, randomAddress, randomAddress);
    }

    // --- Test Managing Owner ---

    function test_SetOwner_RevertIfNotOwner() public {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setOwner(USER_1);
    }

    function test_SetOwner_RevertIfNewOwnerIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        rewardsController.setOwner(address(0));
    }

    function test_SetOwner_Success() public {
        vm.prank(ADMIN);
        rewardsController.setOwner(USER_1);
        assertEq(rewardsController.owner(), USER_1);
    }

    // --- Test Managing NFT Collections ---

    function test_AddNFTCollection_Successful() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionAdded(newCollection, beta, rewardBasis, rewardSharePercentage);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);

        assertTrue(rewardsController.isCollectionWhitelisted(newCollection), "Collection not whitelisted");

        (uint256 configBeta, IRewardsController.RewardBasis configBasis, uint256 configShare) =
            rewardsController.getCollectionData(newCollection);
        assertEq(configBeta, beta, "Beta value incorrect");
        assertEq(uint8(configBasis), uint8(rewardBasis), "RewardBasis incorrect");
        assertEq(configShare, rewardSharePercentage, "RewardSharePercentage incorrect");
    }

    function test_AddNFTCollection_RevertIfNonOwner() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfAddressZero() public {
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.addNFTCollection(address(0), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfCollectionAlreadyExists() public {
        // mockERC721 is already added in the base setup
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(IRewardsController.CollectionAlreadyExists.selector, address(mockERC721))
        );
        rewardsController.addNFTCollection(address(mockERC721), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfInvalidRewardSharePercentage() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, invalidSharePercentage);
    }

    function test_UpdateBeta_Successful() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value
        uint256 oldBeta = BETA_1;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit BetaUpdated(collection, oldBeta, newBeta);
        rewardsController.updateBeta(collection, newBeta);

        (uint256 configBeta,,) = rewardsController.getCollectionData(collection);
        assertEq(configBeta, newBeta, "Beta value not updated");
    }

    function test_UpdateBeta_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_UpdateBeta_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_SetCollectionRewardSharePercentage_Successful() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;
        uint256 oldSharePercentage = VALID_REWARD_SHARE_PERCENTAGE;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);

        (,, uint256 configShare) = rewardsController.getCollectionData(collection);
        assertEq(configShare, newSharePercentage, "RewardSharePercentage not updated");
    }

    function test_SetCollectionRewardSharePercentage_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newSharePercentage = 7500;

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfInvalidSharePercentage() public {
        address collection = address(mockERC721);
        uint256 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setCollectionRewardSharePercentage(collection, invalidSharePercentage);
    }

    function test_RemoveNFTCollection_Successful() public {
        address collection = address(mockERC721);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionRemoved(collection);
        rewardsController.removeNFTCollection(collection);

        assertFalse(rewardsController.isCollectionWhitelisted(collection), "Collection still whitelisted");

        // Trying to access data for a removed collection should revert
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.getCollectionData(collection);
    }

    function test_RemoveNFTCollection_RevertIfNonOwner() public {
        address collection = address(mockERC721);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.removeNFTCollection(collection);
    }

    function test_RemoveNFTCollection_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.removeNFTCollection(collection);
    }

    // --- Test Managing authorizedUpdater ---

    function test_SetTrustedSigner_Successful() public {
        address newUpdater = address(0x9999);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit TrustedSignerUpdated(UPDATER, newUpdater, ADMIN);
        rewardsController.setTrustedSigner(newUpdater);

        assertEq(rewardsController.trustedSigner(), newUpdater, "TrustedSigner not updated");
    }

    function test_SetTrustedSigner_RevertIfNonOwner() public {
        address newUpdater = address(0x9999);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setTrustedSigner(newUpdater);
    }

    function test_SetTrustedSigner_RevertIfAddressZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setTrustedSigner(address(0));
    }

    // Commenting out this test as authorizedUpdaterNonce is not part of the current interface
    /*
    function test_GetAuthorizedUpdaterNonce() public {
        // Initially it should be 0
        assertEq(rewardsController.authorizedUpdaterNonce(), 0, "Initial nonce incorrect");
        
        // After updating, it should increment
        address newUpdater = address(0x9999);
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(newUpdater);
        assertEq(rewardsController.authorizedUpdaterNonce(), 1, "Nonce not incremented after update");
        
        // Update again to check further incrementation
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(address(0x8888));
        assertEq(rewardsController.authorizedUpdaterNonce(), 2, "Nonce not incremented after second update");
    }
    */

    // --- Test Managing maxRewardSharePercentage ---

    function test_SetMaxRewardSharePercentage_Successful() public {
        uint16 newMaxRewardShare = 8000;
        uint16 oldMaxRewardShare = rewardsController.maxRewardSharePercentage();

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit MaxRewardSharePercentageUpdated(oldMaxRewardShare, newMaxRewardShare);
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);

        assertEq(
            rewardsController.maxRewardSharePercentage(), newMaxRewardShare, "MaxRewardSharePercentage not updated"
        );
    }

    function test_SetMaxRewardSharePercentage_RevertIfNonOwner() public {
        uint16 newMaxRewardShare = 8000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfZero() public {
        uint16 zeroRewardShare = 0;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(zeroRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfExceedsMaximumLimit() public {
        uint16 tooHighRewardShare = 10001; // > MAX_REWARD_SHARE_PERCENTAGE_LIMIT (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(tooHighRewardShare);
    }

    function test_SetMaxRewardSharePercentage_AllowsLowerThanExistingCollections() public {
        // This test verifies that setting a lower max doesn't affect existing collections
        uint16 lowerMaxRewardShare = 4000; // Lower than VALID_REWARD_SHARE_PERCENTAGE (5000)

        vm.prank(ADMIN);
        rewardsController.setMaxRewardSharePercentage(lowerMaxRewardShare);

        // Check existing collection still has its original percentage
        (,, uint256 configShare) = rewardsController.getCollectionData(address(mockERC721));
        assertEq(configShare, VALID_REWARD_SHARE_PERCENTAGE, "Existing collection reward share was modified");

        // But adding new collection with higher percentage should fail
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, VALID_REWARD_SHARE_PERCENTAGE);

        // Adding with lower percentage should work
        vm.prank(ADMIN);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, lowerMaxRewardShare);
        assertTrue(
            rewardsController.isCollectionWhitelisted(newCollection), "Collection not added with valid lower percentage"
        );
    }

    // --- Test Fuzzed Initialize ---

    function testFuzz_Initialize_RevertIfAlreadyInitialized(address randomAddress) public {
        vm.assume(randomAddress != address(0));
        vm.prank(ADMIN);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rewardsController.initialize(randomAddress, randomAddress, randomAddress, randomAddress);
    }

    // --- Test Managing Owner ---

    function test_SetOwner_RevertIfNotOwner() public {
        vm.prank(USER_1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setOwner(USER_1);
    }

    function test_SetOwner_RevertIfNewOwnerIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        rewardsController.setOwner(address(0));
    }

    function test_SetOwner_Success() public {
        vm.prank(ADMIN);
        rewardsController.setOwner(USER_1);
        assertEq(rewardsController.owner(), USER_1);
    }

    // --- Test Managing NFT Collections ---

    function test_AddNFTCollection_Successful() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionAdded(newCollection, beta, rewardBasis, rewardSharePercentage);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);

        assertTrue(rewardsController.isCollectionWhitelisted(newCollection), "Collection not whitelisted");

        (uint256 configBeta, IRewardsController.RewardBasis configBasis, uint256 configShare) =
            rewardsController.getCollectionData(newCollection);
        assertEq(configBeta, beta, "Beta value incorrect");
        assertEq(uint8(configBasis), uint8(rewardBasis), "RewardBasis incorrect");
        assertEq(configShare, rewardSharePercentage, "RewardSharePercentage incorrect");
    }

    function test_AddNFTCollection_RevertIfNonOwner() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfAddressZero() public {
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.addNFTCollection(address(0), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfCollectionAlreadyExists() public {
        // mockERC721 is already added in the base setup
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 rewardSharePercentage = 5000;

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(IRewardsController.CollectionAlreadyExists.selector, address(mockERC721))
        );
        rewardsController.addNFTCollection(address(mockERC721), beta, rewardBasis, rewardSharePercentage);
    }

    function test_AddNFTCollection_RevertIfInvalidRewardSharePercentage() public {
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;
        uint16 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, invalidSharePercentage);
    }

    function test_UpdateBeta_Successful() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value
        uint256 oldBeta = BETA_1;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit BetaUpdated(collection, oldBeta, newBeta);
        rewardsController.updateBeta(collection, newBeta);

        (uint256 configBeta,,) = rewardsController.getCollectionData(collection);
        assertEq(configBeta, newBeta, "Beta value not updated");
    }

    function test_UpdateBeta_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_UpdateBeta_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newBeta = 3000; // Corrected beta value

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.updateBeta(collection, newBeta);
    }

    function test_SetCollectionRewardSharePercentage_Successful() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;
        uint256 oldSharePercentage = VALID_REWARD_SHARE_PERCENTAGE;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit CollectionRewardShareUpdated(collection, oldSharePercentage, newSharePercentage);
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);

        (,, uint256 configShare) = rewardsController.getCollectionData(collection);
        assertEq(configShare, newSharePercentage, "RewardSharePercentage not updated");
    }

    function test_SetCollectionRewardSharePercentage_RevertIfNonOwner() public {
        address collection = address(mockERC721);
        uint256 newSharePercentage = 7500;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted
        uint256 newSharePercentage = 7500;

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.setCollectionRewardSharePercentage(collection, newSharePercentage);
    }

    function test_SetCollectionRewardSharePercentage_RevertIfInvalidSharePercentage() public {
        address collection = address(mockERC721);
        uint256 invalidSharePercentage = 10001; // > MAX_REWARD_SHARE_PERCENTAGE (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setCollectionRewardSharePercentage(collection, invalidSharePercentage);
    }

    function test_RemoveNFTCollection_Successful() public {
        address collection = address(mockERC721);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit NFTCollectionRemoved(collection);
        rewardsController.removeNFTCollection(collection);

        assertFalse(rewardsController.isCollectionWhitelisted(collection), "Collection still whitelisted");

        // Trying to access data for a removed collection should revert
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.getCollectionData(collection);
    }

    function test_RemoveNFTCollection_RevertIfNonOwner() public {
        address collection = address(mockERC721);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.removeNFTCollection(collection);
    }

    function test_RemoveNFTCollection_RevertIfCollectionNotWhitelisted() public {
        address collection = address(0xDEAD); // Not whitelisted

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.CollectionNotWhitelisted.selector, collection));
        rewardsController.removeNFTCollection(collection);
    }

    // --- Test Managing authorizedUpdater ---

    function test_SetTrustedSigner_Successful() public {
        address newUpdater = address(0x9999);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit TrustedSignerUpdated(UPDATER, newUpdater, ADMIN);
        rewardsController.setTrustedSigner(newUpdater);

        assertEq(rewardsController.trustedSigner(), newUpdater, "TrustedSigner not updated");
    }

    function test_SetTrustedSigner_RevertIfNonOwner() public {
        address newUpdater = address(0x9999);

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setTrustedSigner(newUpdater);
    }

    function test_SetTrustedSigner_RevertIfAddressZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.AddressZero.selector);
        rewardsController.setTrustedSigner(address(0));
    }

    // Commenting out this test as authorizedUpdaterNonce is not part of the current interface
    /*
    function test_GetAuthorizedUpdaterNonce() public {
        // Initially it should be 0
        assertEq(rewardsController.authorizedUpdaterNonce(), 0, "Initial nonce incorrect");
        
        // After updating, it should increment
        address newUpdater = address(0x9999);
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(newUpdater);
        assertEq(rewardsController.authorizedUpdaterNonce(), 1, "Nonce not incremented after update");
        
        // Update again to check further incrementation
        vm.prank(ADMIN);
        rewardsController.setAuthorizedUpdater(address(0x8888));
        assertEq(rewardsController.authorizedUpdaterNonce(), 2, "Nonce not incremented after second update");
    }
    */

    // --- Test Managing maxRewardSharePercentage ---

    function test_SetMaxRewardSharePercentage_Successful() public {
        uint16 newMaxRewardShare = 8000;
        uint16 oldMaxRewardShare = rewardsController.maxRewardSharePercentage();

        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit MaxRewardSharePercentageUpdated(oldMaxRewardShare, newMaxRewardShare);
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);

        assertEq(
            rewardsController.maxRewardSharePercentage(), newMaxRewardShare, "MaxRewardSharePercentage not updated"
        );
    }

    function test_SetMaxRewardSharePercentage_RevertIfNonOwner() public {
        uint16 newMaxRewardShare = 8000;

        vm.prank(USER_1); // Non-owner
        vm.expectRevert(abi.encodeWithSelector(RewardsController.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.setMaxRewardSharePercentage(newMaxRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfZero() public {
        uint16 zeroRewardShare = 0;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(zeroRewardShare);
    }

    function test_SetMaxRewardSharePercentage_RevertIfExceedsMaximumLimit() public {
        uint16 tooHighRewardShare = 10001; // > MAX_REWARD_SHARE_PERCENTAGE_LIMIT (10000)

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.setMaxRewardSharePercentage(tooHighRewardShare);
    }

    function test_SetMaxRewardSharePercentage_AllowsLowerThanExistingCollections() public {
        // This test verifies that setting a lower max doesn't affect existing collections
        uint16 lowerMaxRewardShare = 4000; // Lower than VALID_REWARD_SHARE_PERCENTAGE (5000)

        vm.prank(ADMIN);
        rewardsController.setMaxRewardSharePercentage(lowerMaxRewardShare);

        // Check existing collection still has its original percentage
        (,, uint256 configShare) = rewardsController.getCollectionData(address(mockERC721));
        assertEq(configShare, VALID_REWARD_SHARE_PERCENTAGE, "Existing collection reward share was modified");

        // But adding new collection with higher percentage should fail
        address newCollection = address(0xABCD);
        uint96 beta = 2000; // Corrected beta value
        IRewardsController.RewardBasis rewardBasis = IRewardsController.RewardBasis.DEPOSIT;

        vm.prank(ADMIN);
        vm.expectRevert(IRewardsController.InvalidRewardSharePercentage.selector);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, VALID_REWARD_SHARE_PERCENTAGE);

        // Adding with lower percentage should work
        vm.prank(ADMIN);
        rewardsController.addNFTCollection(newCollection, beta, rewardBasis, lowerMaxRewardShare);
        assertTrue(
            rewardsController.isCollectionWhitelisted(newCollection), "Collection not added with valid lower percentage"
        );
    }

    // --- Test Fuzzed Initialize ---

    function testFuzz_Initialize_RevertIfAlreadyInitialized(address randomAddress) public {
        vm.assume(randomAddress != address(0));
        vm.prank(ADMIN);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        rewardsController.initialize(randomAddress, randomAddress, randomAddress, randomAddress);
    }
}
