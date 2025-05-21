// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardsController_Test_Base} from "./RewardsController_Test_Base.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol";

import "forge-std/console.sol";

contract ViewTest is RewardsController_Test_Base {
    function setUp() public override {
        super.setUp();
        // Whitelist collection and mint NFT in setup for USER_A, then sync.
        // This ensures totalWeight > 0 for the vault from the start of the tests.
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721), IRewardsController.CollectionType.ERC721, IRewardsController.RewardBasis.DEPOSIT, 1000
        );
        mockERC721.mintSpecific(USER_A, 1); // USER_A gets 1 NFT
        vm.stopPrank();

        vm.startPrank(USER_A);
        // Sync account to update vault's totalWeight
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();
        vm.roll(block.number + 1); // Advance a block after setup sync
    }

    function test_View_Acc() public {
        // Initial state after setUp: USER_A is synced, weight > 0.
        // tokenVault is the vault associated with mockERC721 rewards.
        IRewardsController.AccountInfo memory accountInfo = rewardsController.acc(address(tokenVault), USER_A);
        assertTrue(accountInfo.weight > 0, "Weight should be set after setUp sync");
        assertEq(accountInfo.rewardDebt, 0, "Reward debt should be 0 initially as globalRPW is 0");
        assertEq(accountInfo.accrued, 0, "Accrued should be 0 initially");

        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether); // Transfer 10 ether to RewardsController
        vm.stopPrank();

        vm.roll(block.number + 1); // Advance block after yield generation

        // Refresh rewards; vault totalWeight > 0 from setUp, yield is available
        rewardsController.refreshRewardPerBlock(address(tokenVault));
        vm.roll(block.number + 10); // Advance 10 blocks after refresh for rewards to accrue

        // Advance time for rewards to accrue
        vm.warp(block.timestamp + 100);

        vm.startPrank(USER_A);
        // Sync again to calculate accrued rewards based on new globalRPW
        rewardsController.syncAccount(USER_A, address(mockERC721));
        vm.stopPrank();

        accountInfo = rewardsController.acc(address(tokenVault), USER_A);

        // Add debugging logs
        console.log("Accrued rewards:", accountInfo.accrued);
        console.log("Reward debt:", accountInfo.rewardDebt);
        console.log("Weight:", accountInfo.weight);

        assertTrue(accountInfo.accrued > 0, "Accrued should be updated");
        assertTrue(accountInfo.rewardDebt > 0, "Reward debt should be updated if globalRPW increased");
    }

    function test_View_VaultInfo() public {
        // Initial state after setUp: USER_A is synced, totalWeight > 0 for tokenVault.
        // Vault's lastUpdateBlock was set during its initialization in RewardsController's initialize().
        IRewardsController.VaultInfo memory vaultInfoPreYield = rewardsController.vaults(address(tokenVault));
        assertEq(
            vaultInfoPreYield.rewardPerBlock,
            0,
            "rewardPerBlock should be 0 initially (no yield generated and processed yet)"
        );
        assertTrue(vaultInfoPreYield.totalWeight > 0, "totalWeight should be > 0 after setUp sync");
        uint256 lastUpdateBlockBeforeYield = vaultInfoPreYield.lastUpdateBlock;

        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 5 ether); // Transfer 5 ether to RewardsController
        vm.stopPrank();

        vm.roll(block.number + 1); // Advance block after yield generation

        // Now refresh. AccruedYield > 0 from _generateYieldInLendingManager,
        // totalWeight > 0 from setUp, blockDelta > 0.
        rewardsController.refreshRewardPerBlock(address(tokenVault));

        IRewardsController.VaultInfo memory vaultInfoPostYield = rewardsController.vaults(address(tokenVault));

        assertTrue(vaultInfoPostYield.rewardPerBlock > 0, "rewardPerBlock should be updated");
        assertTrue(vaultInfoPostYield.globalRPW > 0, "globalRPW should be updated");
        assertTrue(vaultInfoPostYield.totalWeight > 0, "totalWeight should still be > 0");
        assertEq(
            vaultInfoPostYield.lastUpdateBlock, block.number, "lastUpdateBlock should be current block after refresh"
        );
    }

    function test_View_UserNonce() public {
        assertEq(rewardsController.userNonce(address(tokenVault), USER_A), 0, "Initial nonce should be 0");

        // We will use mockERC721_2 since mockERC721 is already whitelisted in setUp()
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721_2),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            1000
        );
        mockERC721_2.mintSpecific(USER_A, 1);
        vm.stopPrank();

        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721_2));
        vm.stopPrank();

        // Nonce should be 0 after syncAccount (it's incremented on claim)
        assertEq(rewardsController.userNonce(address(tokenVault), USER_A), 0, "Nonce should still be 0 after sync");

        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        rewardsController.refreshRewardPerBlock(address(tokenVault));

        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721_2));
        vm.stopPrank();

        IRewardsController.Claim[] memory claims = new IRewardsController.Claim[](1);
        claims[0] = IRewardsController.Claim({
            account: USER_A,
            collection: address(mockERC721_2),
            secondsUser: 0,
            secondsColl: 0,
            incRPS: 0,
            yieldSlice: 0,
            nonce: rewardsController.userNonce(address(tokenVault), USER_A),
            deadline: block.timestamp + 1000
        });

        vm.startPrank(USER_A);
        rewardsController.claimLazy(claims, _signClaimLazy(claims, UPDATER_PRIVATE_KEY));
        vm.stopPrank();

        assertEq(rewardsController.userNonce(address(tokenVault), USER_A), 1, "Nonce should be 1 after first claim");

        // Claim again to check increment
        claims[0].nonce = rewardsController.userNonce(address(tokenVault), USER_A);
        vm.startPrank(USER_A);
        rewardsController.claimLazy(claims, _signClaimLazy(claims, UPDATER_PRIVATE_KEY));
        vm.stopPrank();

        assertEq(rewardsController.userNonce(address(tokenVault), USER_A), 2, "Nonce should be 2 after second claim");
    }

    function test_View_UserSecondsPaid() public {
        // This field is currently not used in the new logic, so it should remain 0
        assertEq(rewardsController.userSecondsPaid(address(tokenVault), USER_A), 0, "Initial secondsPaid should be 0");

        // Use mockERC721_alt since mockERC721 is already whitelisted in setUp()
        vm.startPrank(ADMIN);
        rewardsController.whitelistCollection(
            address(mockERC721_alt),
            IRewardsController.CollectionType.ERC721,
            IRewardsController.RewardBasis.DEPOSIT,
            1000
        );
        mockERC721_alt.mintSpecific(USER_A, 1);
        vm.stopPrank();

        vm.startPrank(USER_A);
        rewardsController.syncAccount(USER_A, address(mockERC721_alt));
        vm.stopPrank();

        assertEq(
            rewardsController.userSecondsPaid(address(tokenVault), USER_A), 0, "secondsPaid should remain 0 after sync"
        );

        _generateYieldInLendingManager(100 ether);

        // Transfer some of the yield to the RewardsController to simulate yield accrual
        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(address(rewardsController), 10 ether);
        vm.stopPrank();

        rewardsController.refreshRewardPerBlock(address(tokenVault));

        IRewardsController.Claim[] memory claims = new IRewardsController.Claim[](1);
        claims[0] = IRewardsController.Claim({
            account: USER_A,
            collection: address(mockERC721_alt),
            secondsUser: 0,
            secondsColl: 0,
            incRPS: 0,
            yieldSlice: 0,
            nonce: rewardsController.userNonce(address(tokenVault), USER_A),
            deadline: block.timestamp + 1000
        });

        vm.startPrank(USER_A);
        rewardsController.claimLazy(claims, _signClaimLazy(claims, UPDATER_PRIVATE_KEY));
        vm.stopPrank();

        assertEq(
            rewardsController.userSecondsPaid(address(tokenVault), USER_A), 0, "secondsPaid should remain 0 after claim"
        );
    }

    function test_View_VaultSignatureCompatibility() public {
        // This test ensures the vault() function signature remains unchanged as per ABI compatibility requirement.
        // It primarily checks if the function can be called and returns a value without reverting due to signature mismatch.
        // The actual content of the returned VaultInfo is tested in test_View_VaultInfo.
        IRewardsController.VaultInfo memory vaultInfo = rewardsController.vaults(address(tokenVault));
        assertEq(vaultInfo.rewardPerBlock, 0, "rewardPerBlock should be 0 initially");
    }
}
