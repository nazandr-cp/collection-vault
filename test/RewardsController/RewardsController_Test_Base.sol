/* SPDX-License-Identifier: MIT */
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {RewardsController} from "../../src/RewardsController.sol";
import {LendingManager} from "../../src/LendingManager.sol";
import {CollectionsVault} from "../../src/CollectionsVault.sol";
import {ICollectionsVault} from "../../src/interfaces/ICollectionsVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {
    CErc20Interface,
    CTokenInterface,
    ComptrollerInterface,
    InterestRateModel
} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
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
import {SimpleMockCToken} from "../../src/mocks/SimpleMockCToken.sol";

contract RewardsController_Test_Base is Test {
    using Strings for uint256;

    // Typehashes from RewardsController.sol
    bytes32 public constant CLAIM_TYPEHASH = keccak256(
        "Claim(address account,address collection,uint256 secondsUser,uint256 secondsColl,uint256 incRPS,uint256 yieldSlice,uint256 nonce,uint256 deadline)"
    );

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
    uint256 constant BETA_1 = 1000; // Was 0.1 ether (10%)
    uint256 constant BETA_2 = 500; // Was 0.05 ether (5%)
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
    CollectionsVault internal tokenVault;
    IERC20 internal rewardToken;
    MockERC20 internal mockERC20;
    MockERC721 internal mockERC721;
    MockERC721 internal mockERC721_2;
    MockERC721 internal mockERC721_alt;
    SimpleMockCToken internal mockCToken;
    ProxyAdmin public proxyAdmin;

    uint256 constant INITIAL_EXCHANGE_RATE = 2e28;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("mainnet", FORK_BLOCK_NUMBER);
        vm.selectFork(forkId);
        vm.roll(block.number + 1);

        rewardToken = IERC20(DAI_ADDRESS);

        vm.startPrank(OWNER);
        mockERC20 = new MockERC20("Mock Token", "MOCK", 18, 0); // Added initialSupply
        mockERC721 = new MockERC721("Mock NFT 1", "MNFT1");
        mockERC721_2 = new MockERC721("Mock NFT 2", "MNFT2");
        mockERC721_alt = new MockERC721("Mock NFT Alt", "MNFTA");
        // mockCToken = new SimpleMockCToken(address(rewardToken));
        // Update the constructor call for SimpleMockCToken to match its definition
        mockCToken = new SimpleMockCToken(
            address(rewardToken), // underlyingAddress_
            ComptrollerInterface(payable(address(this))), // mock ComptrollerInterface
            InterestRateModel(payable(address(this))), // mock InterestRateModel
            INITIAL_EXCHANGE_RATE, // initialExchangeRateMantissa_
            "Mock cDAI", // name_
            "mcDAI", // symbol_
            18, // decimals_
            payable(OWNER) // admin_
        );
        // mockCToken.setExchangeRate(INITIAL_EXCHANGE_RATE); // This function does not exist on SimpleMockCToken

        lendingManager = new LendingManager(OWNER, address(1), address(this), address(rewardToken), address(mockCToken));

        // Use ADMIN as the initialAdmin for CollectionsVault, consistent with RewardsController owner
        tokenVault = new CollectionsVault(rewardToken, "Vaulted DAI Test", "vDAIt", ADMIN, address(lendingManager));

        lendingManager.revokeVaultRole(address(1));
        lendingManager.grantVaultRole(address(tokenVault));

        // Deploy RewardsController implementation and proxy first
        rewardsControllerImpl = new RewardsController(address(1)); // Provide a dummy address for priceOracleAddress_

        // Transfer ownership of mockERC20 to ADMIN for consistent access control
        mockERC20.transferOwnership(ADMIN);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        proxyAdmin = new ProxyAdmin(ADMIN);
        
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            ADMIN, // RewardsController owner is ADMIN
            address(tokenVault), // Corrected: This is the ICollectionsVault address
            AUTHORIZED_UPDATER // Corrected: This is the initialClaimSigner
                // AUTHORIZED_UPDATER // Original extra argument removed
        );
        TransparentUpgradeableProxy proxy;
        try new TransparentUpgradeableProxy(address(rewardsControllerImpl), address(proxyAdmin), initData) returns (
            TransparentUpgradeableProxy _proxy
        ) {
            proxy = _proxy;
        } catch Error(string memory reason) {
            console.log("Proxy deployment failed:", reason);
            revert("Proxy deployment failed");
        } catch (bytes memory lowLevelData) {
            console.log("Proxy deployment failed with low-level data:", string(lowLevelData));
            revert("Proxy deployment failed with low-level data");
        }
        rewardsController = RewardsController(address(proxy));
        
        // Grant REWARDS_CONTROLLER_ROLE to rewardsController on the tokenVault
        // This needs to be done by an admin of tokenVault (ADMIN in this case)
        tokenVault.setRewardsControllerRole(address(rewardsController));
        vm.stopPrank();

        // LendingManager roles are managed by OWNER (who has ADMIN_ROLE on LendingManager)
        vm.startPrank(OWNER);
        lendingManager.revokeRewardsControllerRole(address(this));
        lendingManager.grantRewardsControllerRole(address(rewardsController));
        vm.stopPrank();

        // RewardsController onlyOwner functions are called by ADMIN
        // vm.startPrank(ADMIN);
        // rewardsController.whitelistCollection(
        //     address(mockERC721),
        //     IRewardsController.CollectionType.ERC721,
        //     IRewardsController.RewardBasis.BORROW,
        //     uint16(BETA_1)
        // );
        // rewardsController.whitelistCollection(
        //     address(mockERC721_2),
        //     IRewardsController.CollectionType.ERC721,
        //     IRewardsController.RewardBasis.DEPOSIT,
        //     uint16(BETA_2)
        // );
        // rewardsController.whitelistCollection(
        //     address(mockERC721_alt),
        //     IRewardsController.CollectionType.ERC721,
        //     IRewardsController.RewardBasis.DEPOSIT,
        //     uint16(VALID_REWARD_SHARE_PERCENTAGE)
        // );
        // vm.stopPrank(); // Stop pranking as ADMIN

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

    function tearDown() public virtual {
        // Clear the contract code to ensure a clean state for each test
        vm.etch(address(rewardsController), bytes(""));
        vm.etch(address(rewardsControllerImpl), bytes(""));
        vm.etch(address(lendingManager), bytes(""));
        vm.etch(address(tokenVault), bytes(""));
        vm.etch(address(proxyAdmin), bytes(""));
        vm.etch(address(mockERC20), bytes(""));
        vm.etch(address(mockERC721), bytes(""));
        vm.etch(address(mockERC721_2), bytes(""));
        vm.etch(address(mockERC721_alt), bytes(""));
        vm.etch(address(mockCToken), bytes(""));
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
                uint256 emittedAmount = abi.decode(entries[i].data, (uint256));
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
                uint256 emittedAmount = abi.decode(entries[i].data, (uint256));
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

            // uint256 increment = mockCToken.accrualIncrement();

            // if (finalTargetExchangeRate > increment) {
            //     exchangeRateToSetInitially =
            //         finalTargetExchangeRate -
            //         increment;
            // } else {
            //     exchangeRateToSetInitially = finalTargetExchangeRate;
            //     if (
            //         finalTargetExchangeRate > 0 &&
            //         finalTargetExchangeRate <= increment
            //     ) {}
            // }
            if (exchangeRateToSetInitially == 0 && (currentPrincipal > 0 || targetYield > 0)) {
                exchangeRateToSetInitially = 1;
            }
            // mockCToken.setExchangeRate(exchangeRateToSetInitially);
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

        // uint256 indexDelta = endIndex - startIndex;
        // (
        //     uint96 betaLocal,
        //     uint16 rewardSharePercentageLocal
        // ) = rewardsController.collectionConfigs(collection);
        IRewardsController.RewardBasis rewardBasisLocal = rewardsControllerImpl.collectionRewardBasis(collection);
        bool isWhitelisted = rewardsController.isCollectionWhitelisted(collection);

        // // Simplified replication of RewardsController._calculateRewardsWithDelta
        // uint256 yieldReward = (balanceDuringPeriod * indexDelta) / startIndex; // Assuming startIndex is the 'lastRewardIndex' for the period

        // uint256 beta = betaLocal;
        // uint256 boostFactor = rewardsController.calculateBoost(
        //     nftBalanceDuringPeriod,
        //     beta
        // );

        // uint256 bonusReward = (yieldReward * boostFactor) / PRECISION; // PRECISION is 1e18
        // uint256 totalYieldWithBoost = yieldReward + bonusReward;

        // rawReward =
        //     (totalYieldWithBoost * rewardSharePercentage) /
        //     MAX_REWARD_SHARE_PERCENTAGE;

        // return rawReward;
    }

    function _signClaimLazy(IRewardsController.Claim[] memory claims, uint256 privateKey)
        internal
        view
        virtual
        returns (bytes memory)
    {
        bytes32 claimsHash = keccak256(abi.encode(claims));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), claimsHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
