/* SPDX-License-Identifier: MIT */
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RewardsController} from "../../src/RewardsController.sol";
import {LendingManager} from "../../src/LendingManager.sol";
import {ERC4626Vault} from "../../src/ERC4626Vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {ILendingManager} from "../../src/interfaces/ILendingManager.sol";
import {IRewardsController} from "../../src/interfaces/IRewardsController.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol";
import {MockCToken} from "../../src/mocks/MockCToken.sol";

contract RewardsController_Test_Base is Test {
    using Strings for uint256;

    bytes32 public constant BALANCE_UPDATES_ARRAYS_TYPEHASH = keccak256(
        "BalanceUpdates(address[] users,address[] collections,uint256[] blockNumbers,int256[] nftDeltas,int256[] balanceDeltas,uint256 nonce)"
    );
    bytes32 public constant BALANCE_UPDATE_DATA_TYPEHASH =
        keccak256("BalanceUpdateData(address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)");
    bytes32 public constant USER_BALANCE_UPDATES_TYPEHASH =
        keccak256("UserBalanceUpdates(address user,BalanceUpdateData[] updates,uint256 nonce)");

    address constant USER_A = address(0xAAA);
    address constant USER_B = address(0xBBB);
    address constant USER_C = address(0xCCC);
    address constant NFT_COLLECTION_1 = address(0xC1);
    address constant NFT_COLLECTION_2 = address(0xC2);
    address constant NFT_COLLECTION_3 = address(0xC3);
    address constant OWNER = address(0x001);
    address constant ADMIN = address(0xAD01);
    address constant OTHER_ADDRESS = address(0x123);
    address constant NEW_UPDATER = address(0x000000000000000000000000000000000000000d);
    address constant AUTHORIZED_UPDATER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant UPDATER_PRIVATE_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant OWNER_PRIVATE_KEY = 0x1000000000000000000000000000000000000000000000000000000000000001; // Dummy PK for OWNER
    uint256 constant PRECISION = 1e18;
    uint256 constant BETA_1 = 0.1 ether;
    uint256 constant BETA_2 = 0.05 ether;
    uint256 constant MAX_REWARD_SHARE_PERCENTAGE = 10000;
    uint256 constant VALID_REWARD_SHARE_PERCENTAGE = 5000;
    uint256 constant INVALID_REWARD_SHARE_PERCENTAGE = 10001;
    address constant CDAI_ADDRESS = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint256 constant FORK_BLOCK_NUMBER = 19670000;
    address constant DAI_WHALE = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    RewardsController internal rewardsController;
    RewardsController internal rewardsControllerImpl;
    LendingManager internal lendingManager;
    ERC4626Vault internal tokenVault;
    IERC20 internal rewardToken;
    MockERC20 internal mockERC20;
    MockERC721 internal mockERC721;
    MockERC721 internal mockERC721_2;
    MockERC721 internal mockERC721_alt;
    MockCToken internal mockCToken;
    ProxyAdmin public proxyAdmin;

    uint256 constant INITIAL_EXCHANGE_RATE = 2e28;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("mainnet", FORK_BLOCK_NUMBER);
        vm.selectFork(forkId);

        rewardToken = IERC20(DAI_ADDRESS);

        vm.startPrank(OWNER);

        mockERC20 = new MockERC20("Mock Token", "MOCK", 18);
        mockERC721 = new MockERC721("Mock NFT 1", "MNFT1");
        mockERC721_2 = new MockERC721("Mock NFT 2", "MNFT2");
        mockERC721_alt = new MockERC721("Mock NFT Alt", "MNFTA");
        mockCToken = new MockCToken(address(rewardToken));
        mockCToken.setExchangeRate(INITIAL_EXCHANGE_RATE);

        lendingManager = new LendingManager(OWNER, address(1), address(this), address(rewardToken), address(mockCToken));

        tokenVault = new ERC4626Vault(rewardToken, "Vaulted DAI Test", "vDAIt", OWNER, address(lendingManager));

        lendingManager.revokeVaultRole(address(1));
        lendingManager.grantVaultRole(address(tokenVault));

        rewardsControllerImpl = new RewardsController();

        vm.stopPrank();
        vm.startPrank(ADMIN);
        proxyAdmin = new ProxyAdmin(ADMIN);
        vm.stopPrank();

        vm.startPrank(ADMIN); // Changed OWNER to ADMIN for RC deployment and ownership
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            ADMIN, // RewardsController owner is ADMIN
            address(lendingManager),
            address(tokenVault),
            AUTHORIZED_UPDATER
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(rewardsControllerImpl), address(proxyAdmin), initData);
        rewardsController = RewardsController(address(proxy));
        vm.stopPrank(); // Stop pranking as ADMIN

        // LendingManager roles are managed by OWNER (who has ADMIN_ROLE on LendingManager)
        vm.startPrank(OWNER);
        lendingManager.revokeRewardsControllerRole(address(this));
        lendingManager.grantRewardsControllerRole(address(rewardsController));
        vm.stopPrank();

        // RewardsController onlyOwner functions are called by ADMIN
        vm.startPrank(ADMIN);
        rewardsController.addNFTCollection(
            address(mockERC721), BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        rewardsController.addNFTCollection(
            address(mockERC721_2), BETA_2, IRewardsController.RewardBasis.DEPOSIT, VALID_REWARD_SHARE_PERCENTAGE
        );
        rewardsController.addNFTCollection(
            address(mockERC721_alt), BETA_1, IRewardsController.RewardBasis.DEPOSIT, VALID_REWARD_SHARE_PERCENTAGE
        );
        vm.stopPrank(); // Stop pranking as ADMIN

        uint256 initialFunding = 1_000_000 ether;
        uint256 userFunding = 10_000 ether;
        deal(DAI_ADDRESS, DAI_WHALE, initialFunding * 2);
        deal(address(rewardToken), address(lendingManager), initialFunding);

        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(USER_A, userFunding);
        rewardToken.transfer(USER_B, userFunding);
        rewardToken.transfer(USER_C, userFunding);

        uint256 initialVaultDeposit = 1000 ether;
        if (userFunding >= initialVaultDeposit) {
            rewardToken.approve(address(tokenVault), initialVaultDeposit);
            tokenVault.depositForCollection(initialVaultDeposit, USER_A, address(mockERC721));
        }
        vm.stopPrank();

        vm.startPrank(USER_C);
        IRewardsController.BalanceUpdateData[] memory noSimUpdatesForClaim;
        rewardsController.claimRewardsForCollection(address(mockERC721_alt), noSimUpdatesForClaim);
        vm.stopPrank();

        vm.label(OWNER, "OWNER");
        vm.label(ADMIN, "ADMIN");
        vm.label(AUTHORIZED_UPDATER, "AUTHORIZED_UPDATER");
        vm.label(USER_A, "USER_A");
        vm.label(USER_B, "USER_B");
        vm.label(USER_C, "USER_C");
        vm.label(address(rewardsController), "RewardsController (Proxy)");
        vm.label(address(rewardsControllerImpl), "RewardsController (Impl)");
        vm.label(address(lendingManager), "LendingManager");
        vm.label(address(tokenVault), "TokenVault");
        vm.label(address(proxyAdmin), "ProxyAdmin");
        vm.label(address(mockERC721), "NFT_COLLECTION_1 (Mock)");
        vm.label(address(mockERC721_2), "NFT_COLLECTION_2 (Mock)");
        vm.label(address(mockERC721_alt), "NFT_COLLECTION_ALT (Mock)");
        vm.label(NFT_COLLECTION_3, "NFT_COLLECTION_3 (Constant, Non-WL)");
    }

    function _buildDomainSeparator() internal view returns (bytes32) {
        bytes32 typeHashDomain =
            keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));
        bytes32 nameHashDomain = keccak256(bytes("RewardsController"));
        bytes32 versionHashDomain = keccak256(bytes("1"));
        return keccak256(
            abi.encode(typeHashDomain, nameHashDomain, versionHashDomain, block.chainid, address(rewardsController))
        );
    }

    function _hashBalanceUpdates(IRewardsController.BalanceUpdateData[] memory updates)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory dataHashes = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            dataHashes[i] = keccak256(
                abi.encode(
                    BALANCE_UPDATE_DATA_TYPEHASH,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].balanceDelta
                )
            );
        }
        return keccak256(abi.encodePacked(dataHashes));
    }

    function _signUserBalanceUpdates(
        address user,
        IRewardsController.BalanceUpdateData[] memory updates,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        bytes32 domainSeparator = _buildDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        // Minimal logging for USER_B's signature in relevant tests
        if (user == USER_B && nonce == 1) {
            // Conditions specific to the failing scenario
            console.log("--- Test Sig Gen (USER_B, nonce 1) ---");
            console.log("_signUserBalanceUpdates: user (param):");
            console.logAddress(user);
            console.log("_signUserBalanceUpdates: nonce_for_struct:");
            console.logUint(nonce);
            console.log("_signUserBalanceUpdates: updatesHash_for_struct:");
            console.logBytes32(updatesHash);
            console.log("_signUserBalanceUpdates: structHash:");
            console.logBytes32(structHash);
            console.log("_signUserBalanceUpdates: domainSeparator:");
            console.logBytes32(domainSeparator);
            console.log("_signUserBalanceUpdates: digest:");
            console.logBytes32(digest);
            console.log("--------------------------------------");
        }

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _signBalanceUpdatesArrays(
        address[] memory users,
        address[] memory collections,
        uint256[] memory blockNumbers,
        int256[] memory nftDeltas,
        int256[] memory balanceDeltas,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 structHash = keccak256(
            abi.encode(
                BALANCE_UPDATES_ARRAYS_TYPEHASH,
                keccak256(abi.encodePacked(users)),
                keccak256(abi.encodePacked(collections)),
                keccak256(abi.encodePacked(blockNumbers)),
                keccak256(abi.encodePacked(nftDeltas)),
                keccak256(abi.encodePacked(balanceDeltas)),
                nonce
            )
        );
        bytes32 domainSeparator = _buildDomainSeparator();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    function _callProcessUserBalanceUpdates_WithNonce(
        address user,
        address collectionToUpdate, // Renamed for clarity in new function
        uint256 updateBlockNumber, // Renamed for clarity in new function
        int256 nftDelta,
        int256 balanceDelta,
        uint256 nonceToUse
    ) internal {
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collectionToUpdate,
            blockNumber: updateBlockNumber,
            nftDelta: nftDelta,
            balanceDelta: balanceDelta
        });

        bytes memory signature = _signUserBalanceUpdates(user, updates, nonceToUse, UPDATER_PRIVATE_KEY);

        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, signature);
    }

    function _processSingleUserUpdate(
        address user,
        address collection,
        uint256 blockNum,
        int256 nftDelta,
        int256 balanceDelta
    ) internal {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        _callProcessUserBalanceUpdates_WithNonce(user, collection, blockNum, nftDelta, balanceDelta, nonce);
    }

    function _assertRewardsClaimedForCollectionLog(
        Vm.Log[] memory entries,
        address expectedUser,
        address expectedCollection,
        uint256 expectedAmount,
        uint256 delta
    ) internal pure {
        bytes32 expectedTopic0 = keccak256("RewardsClaimedForCollection(address,address,uint256)");
        bytes32 userTopic = bytes32(uint256(uint160(expectedUser)));
        bytes32 collectionTopic = bytes32(uint256(uint160(expectedCollection)));
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length == 3 && entries[i].topics[0] == expectedTopic0
                    && entries[i].topics[1] == userTopic && entries[i].topics[2] == collectionTopic
            ) {
                (uint256 emittedAmount) = abi.decode(entries[i].data, (uint256));
                assertApproxEqAbs(emittedAmount, expectedAmount, delta, "RewardsClaimedForCollection amount mismatch");
                found = true;
                break;
            }
        }
        assertTrue(found, "RewardsClaimedForCollection log not found or topics mismatch");
    }

    function _assertRewardsClaimedForAllLog(
        Vm.Log[] memory entries,
        address expectedUser,
        uint256 expectedAmount,
        uint256 delta
    ) internal pure {
        bytes32 expectedTopic0 = keccak256("RewardsClaimedForAll(address,uint256)");
        bytes32 userTopic = bytes32(uint256(uint160(expectedUser)));
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length == 2 && entries[i].topics[0] == expectedTopic0
                    && entries[i].topics[1] == userTopic
            ) {
                (uint256 emittedAmount) = abi.decode(entries[i].data, (uint256));
                assertApproxEqAbs(emittedAmount, expectedAmount, delta, "RewardsClaimedForAll amount mismatch");
                found = true;
                break;
            }
        }
        assertTrue(found, "RewardsClaimedForAll log not found or user mismatch");
    }

    function _assertYieldTransferCappedLog(
        Vm.Log[] memory entries,
        address expectedUser,
        uint256 expectedTotalDue,
        uint256 expectedActualReceived,
        uint256 delta
    ) internal pure {
        bytes32 expectedTopic0 = keccak256("YieldTransferCapped(address,uint256,uint256)");
        bytes32 userTopic = bytes32(uint256(uint160(expectedUser)));
        bool found = false;
        for (uint256 i = 0; i < entries.length; i++) {
            if (
                entries[i].topics.length == 2 && entries[i].topics[0] == expectedTopic0
                    && entries[i].topics[1] == userTopic
            ) {
                (uint256 emittedTotalDue, uint256 emittedActualReceived) =
                    abi.decode(entries[i].data, (uint256, uint256));
                assertApproxEqAbs(emittedTotalDue, expectedTotalDue, delta, "YieldTransferCapped totalDue mismatch");
                assertApproxEqAbs(
                    emittedActualReceived, expectedActualReceived, 1, "YieldTransferCapped actualReceived mismatch"
                );
                found = true;
                break;
            }
        }
        assertTrue(found, "YieldTransferCapped log not found or user mismatch");
    }

    function _generateYieldInLendingManager(uint256 targetYield) internal {
        uint256 currentPrincipal = lendingManager.totalPrincipalDeposited();
        if (currentPrincipal == 0) {
            uint256 principalAmount = 100 ether;
            vm.startPrank(DAI_WHALE);
            rewardToken.transfer(address(tokenVault), principalAmount);
            vm.stopPrank();

            vm.startPrank(address(tokenVault));
            rewardToken.approve(address(lendingManager), principalAmount);
            lendingManager.depositToLendingProtocol(principalAmount);
            vm.stopPrank();
            currentPrincipal = lendingManager.totalPrincipalDeposited();
        }

        uint256 cTokenBalanceOfLM = mockCToken.balanceOf(address(lendingManager));
        uint256 exchangeRateToSetInitially;

        if (cTokenBalanceOfLM == 0) {
            if (targetYield > 0) {}
            exchangeRateToSetInitially = mockCToken.exchangeRateStored();
        } else {
            uint256 finalTargetTotalUnderlying = currentPrincipal + targetYield;

            uint256 finalTargetExchangeRate = (finalTargetTotalUnderlying * 1e18) / cTokenBalanceOfLM;

            uint256 increment = mockCToken.accrualIncrement();

            if (finalTargetExchangeRate > increment) {
                exchangeRateToSetInitially = finalTargetExchangeRate - increment;
            } else {
                exchangeRateToSetInitially = finalTargetExchangeRate;
                if (finalTargetExchangeRate > 0 && finalTargetExchangeRate <= increment) {}
            }
            if (exchangeRateToSetInitially == 0 && (currentPrincipal > 0 || targetYield > 0)) {
                exchangeRateToSetInitially = 1;
            }
            mockCToken.setExchangeRate(exchangeRateToSetInitially);
        }

        vm.startPrank(DAI_WHALE);
        uint256 fundingForMockCToken = targetYield > 0 ? targetYield * 5 : (100 ether / 2);
        rewardToken.transfer(address(mockCToken), fundingForMockCToken);
        vm.stopPrank();

        uint256 lmTotalAssetsBeforeImplicitAccrual = lendingManager.totalAssets();
        uint256 lmAvailableYieldBeforeImplicitAccrual = lmTotalAssetsBeforeImplicitAccrual > currentPrincipal
            ? lmTotalAssetsBeforeImplicitAccrual - currentPrincipal
            : 0;

        if (targetYield > 0) {
            deal(address(rewardToken), address(lendingManager), targetYield);
        }
    }

    function _calculateRewardsManually(
        address user, // Not directly used in this simplified version, but good for context
        address collection,
        uint256 nftBalanceDuringPeriod,
        uint256 balanceDuringPeriod,
        uint256 startIndex,
        uint256 endIndex
    ) internal view returns (uint256 rawReward) {
        user; // Suppress unused variable warning

        if (nftBalanceDuringPeriod == 0 || balanceDuringPeriod == 0 || startIndex == 0 || endIndex <= startIndex) {
            return 0;
        }

        uint256 indexDelta = endIndex - startIndex;
        (uint96 betaLocal, uint16 rewardSharePercentageLocal) = rewardsController.collectionConfigs(collection);
        IRewardsController.RewardBasis rewardBasisLocal = rewardsController.collectionRewardBasis(collection);
        bool isWhitelisted = rewardsController.isCollectionWhitelisted(collection);
        uint256 rewardSharePercentage = rewardSharePercentageLocal;

        // Simplified replication of RewardsController._calculateRewardsWithDelta
        uint256 yieldReward = (balanceDuringPeriod * indexDelta) / startIndex; // Assuming startIndex is the 'lastRewardIndex' for the period

        uint256 beta = betaLocal;
        uint256 boostFactor = rewardsController.calculateBoost(nftBalanceDuringPeriod, beta);

        uint256 bonusReward = (yieldReward * boostFactor) / PRECISION; // PRECISION is 1e18
        uint256 totalYieldWithBoost = yieldReward + bonusReward;

        rawReward = (totalYieldWithBoost * rewardSharePercentage) / MAX_REWARD_SHARE_PERCENTAGE;

        return rawReward;
    }
}
