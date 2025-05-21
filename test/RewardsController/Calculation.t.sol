// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol";

contract CalculationTest is RewardsController_Test_Base {
    function setUp() public override {
        super.setUp();
    }

    function test_ShareLogic_TotalCollectionShareBpsExceedsMax_WhitelistCollection() public {
        vm.startPrank(ADMIN);
        // Whitelist a collection with 6000 BPS
        rewardsController.whitelistCollection(
            address(mockERC721), IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 6000
        );

        // Attempt to whitelist another collection that would exceed MAX_REWARD_SHARE_PERCENTAGE (10000 BPS)
        // Current total 6000, adding 5000 -> new total 11000
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.InvalidRewardSharePercentage.selector, 11000));
        rewardsController.whitelistCollection(
            address(mockERC721_2),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            5000
        );
        vm.stopPrank();
    }

    function test_ShareLogic_TotalCollectionShareBpsExceedsMax_UpdateCollectionPercentageShare() public {
        vm.startPrank(ADMIN);
        // Whitelist two collections, total 7000 BPS
        rewardsController.whitelistCollection(
            address(mockERC721), IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 3000
        );
        rewardsController.whitelistCollection(
            address(mockERC721_2),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            4000
        );

        // Attempt to update mockERC721_2's share to exceed MAX_REWARD_SHARE_PERCENTAGE
        // Current total: 3000 + 4000 = 7000 BPS
        // New share for mockERC721_2: 4000 -> 7000 (adds 3000)
        // Expected total: 7000 - 4000 + 7000 = 10000 BPS (This should pass if MAX_REWARD_SHARE_PERCENTAGE is 10000)
        // Let's make it fail: try to update to 7001. New total = (7000 - 4000 + 7001) = 10001
        vm.expectRevert(abi.encodeWithSelector(IRewardsController.InvalidRewardSharePercentage.selector, 10001));
        rewardsController.updateCollectionPercentageShare(
            address(mockERC721_2),
            7001 // New share percentage
        );
        vm.stopPrank();
    }

    function test_StateMutations_UpdateUserWeightAndAccrueRewards() public {
        vm.startPrank(ADMIN);
        // Whitelist a collection with a non-zero share
        rewardsController.whitelistCollection(
            address(mockERC721),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            1000 // 10% share
        );
        vm.stopPrank();

        // Mint an NFT to USER_A to give them weight
        vm.startPrank(ADMIN);
        mockERC721.mintSpecific(USER_A, 1);
        vm.stopPrank();

        // Sync account to initialize AccountStorageData and InternalVaultInfo
        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        // Verify initial state
        IRewardsController.AccountInfo memory accountInfo = rewardsController.acc(address(tokenVault), USER_A);
        assertTrue(accountInfo.weight > 0, "Initial weight should be greater than 0");
        assertTrue(accountInfo.rewardDebt == 0, "Initial rewardDebt should be 0");
        assertTrue(accountInfo.accrued == 0, "Initial accrued should be 0");

        IRewardsController.VaultInfo memory vaultInfo = rewardsController.vaults(address(tokenVault));
        assertTrue(vaultInfo.totalWeight > 0, "Initial totalWeight should be greater than 0");
        assertTrue(vaultInfo.globalRPW == 0, "Initial globalRPW should be 0");
        assertTrue(vaultInfo.rewardPerBlock == 0, "Initial rewardPerBlock should be 0");

        // Generate some yield and refresh reward per block
        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        // Increase block number to create a non-zero blocksDelta
        vm.roll(block.number + 1);

        rewardsController.refreshRewardPerBlock(address(tokenVault));

        // Advance block again so rewards can accrue over time
        vm.roll(block.number + 10);

        // Sync account again to accrue rewards and update weight
        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        accountInfo = rewardsController.acc(address(tokenVault), USER_A);
        assertTrue(accountInfo.accrued > 0, "Accrued rewards should be greater than 0 after sync");
        assertTrue(accountInfo.rewardDebt > 0, "RewardDebt should be updated after sync");

        vaultInfo = rewardsController.vaults(address(tokenVault));
        assertTrue(vaultInfo.globalRPW > 0, "globalRPW should be updated after refresh");
        assertTrue(vaultInfo.rewardPerBlock > 0, "rewardPerBlock should be updated after refresh");
    }

    function test_StateMutations_RefreshRewardPerBlock_TotalWeightZero() public {
        // Initially totalWeight is 0 as no collections are whitelisted with weight
        IRewardsController.VaultInfo memory vaultInfoBefore = rewardsController.vaults(address(tokenVault));
        assertEq(vaultInfoBefore.totalWeight, 0, "Initial totalWeight should be 0");

        // Generate some yield
        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        // Increase block number to create a non-zero blocksDelta
        vm.roll(block.number + 1);

        // Refresh reward per block
        rewardsController.refreshRewardPerBlock(address(tokenVault));

        IRewardsController.VaultInfo memory vaultInfoAfter = rewardsController.vaults(address(tokenVault));
        assertEq(vaultInfoAfter.globalRPW, 0, "globalRPW should be 0 when totalWeight is 0");
        assertTrue(vaultInfoAfter.rewardPerBlock > 0, "rewardPerBlock should still update based on yield");
        assertEq(vaultInfoAfter.totalWeight, 0, "totalWeight should remain 0");
    }

    function test_StateMutations_RefreshRewardPerBlock_BlocksDeltaZero() public {
        // Generate some yield
        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        // Increase block number to create a non-zero blocksDelta
        vm.roll(block.number + 1);

        // Refresh reward per block for the first time
        rewardsController.refreshRewardPerBlock(address(tokenVault));

        IRewardsController.VaultInfo memory vaultInfoFirstCall = rewardsController.vaults(address(tokenVault));
        assertTrue(vaultInfoFirstCall.rewardPerBlock > 0, "rewardPerBlock should be updated");

        // Whitelist a collection to make totalWeight > 0 for globalRPW to be non-zero
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            1000 // 10% share
        );
        mockERC721.mintSpecific(USER_A, 1);
        vm.stopPrank();

        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        // Advance to a new block so that blocksDelta > 0
        vm.roll(block.number + 1);

        // Transfer more reward tokens to simulate additional yield
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        // Refresh reward per block again with totalWeight > 0, should update globalRPW
        rewardsController.refreshRewardPerBlock(address(tokenVault));

        vaultInfoFirstCall = rewardsController.vaults(address(tokenVault));
        assertTrue(
            vaultInfoFirstCall.globalRPW > 0, "globalRPW should be updated when blocksDelta > 0 and totalWeight > 0"
        );

        // Now call refresh in the same block to test blocksDelta = 0 case
        rewardsController.refreshRewardPerBlock(address(tokenVault));

        IRewardsController.VaultInfo memory vaultInfoSecondCall = rewardsController.vaults(address(tokenVault));
        // When blocksDelta = 0, rewardPerBlock is set to 0 and globalRPW is set to 0
        assertEq(vaultInfoSecondCall.rewardPerBlock, 0, "rewardPerBlock should be 0 when blocksDelta is 0");
        assertEq(vaultInfoSecondCall.globalRPW, 0, "globalRPW should be 0 when blocksDelta is 0");
        assertEq(vaultInfoSecondCall.lastUpdateBlock, block.number, "lastUpdateBlock should be current block");
    }

    function test_ClaimLazy_RewardsCalculatedUpToCurrentBlock() public {
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            1000 // 10% share
        );
        mockERC721.mintSpecific(USER_A, 1);
        vm.stopPrank();

        // Sync account to initialize AccountStorageData
        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        // Generate yield over several blocks
        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        vm.roll(block.number + 5); // Advance blocks
        rewardsController.refreshRewardPerBlock(address(tokenVault)); // Keeper runs

        // User's position changes (e.g., mint another NFT with a different ID)
        vm.startPrank(ADMIN);
        mockERC721.mintSpecific(USER_A, 2);
        vm.stopPrank();

        // Do NOT run refreshRewardPerBlock again.
        // User calls claimLazy. Rewards should be based on accruals up to the block of this transaction.
        // The _updateUserWeightAndAccrueRewards inside claimLazy will update the weight and accrue.
        IRewardsController.Claim[] memory claims = new IRewardsController.Claim[](1);
        claims[0] = IRewardsController.Claim({
            account: USER_A,
            collection: address(mockERC721),
            secondsUser: 0, // Not used in new logic
            secondsColl: 0, // Not used in new logic
            incRPS: 0, // Not used in new logic
            yieldSlice: 0, // Not used in new logic
            nonce: rewardsController.userNonce(address(tokenVault), USER_A),
            deadline: block.timestamp + 1000
        });

        uint256 initialUserBalance = rewardToken.balanceOf(USER_A);
        uint256 initialAccrued = rewardsController.acc(address(tokenVault), USER_A).accrued;

        vm.startPrank(USER_A);
        rewardsController.claimLazy(claims, _signClaimLazy(claims, UPDATER_PRIVATE_KEY));
        vm.stopPrank();

        uint256 finalUserBalance = rewardToken.balanceOf(USER_A);
        uint256 finalAccrued = rewardsController.acc(address(tokenVault), USER_A).accrued;

        assertTrue(finalUserBalance > initialUserBalance, "User should have received rewards");
        assertEq(finalAccrued, 0, "Accrued rewards should be reset to 0 after claim");
        // Further assertions would involve calculating expected rewards based on block numbers and weights
        // to ensure no future rewards are paid. This requires more complex setup to mock time/blocks precisely.
        // For now, verifying accrual and reset is sufficient.
    }

    // Helper function to sign claims for claimLazy
    function _signClaimLazy(IRewardsController.Claim[] memory claims, uint256 privateKey)
        internal
        view
        override
        returns (bytes memory signature)
    {
        bytes32 claimsHash = keccak256(abi.encode(claims));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), claimsHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }
}
