// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm, console} from "forge-std/Test.sol";
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
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC721} from "../../src/mocks/MockERC721.sol"; // Import MockERC721
import {MockLendingManager} from "../../src/mocks/MockLendingManager.sol"; // Import MockLendingManager
import {MockCToken} from "../../src/mocks/MockCToken.sol"; // Import MockCToken

contract RewardsController_Test_Base is Test {
    using Strings for uint256;

    bytes32 public constant USER_BALANCE_UPDATE_DATA_TYPEHASH = keccak256(
        "UserBalanceUpdateData(address user,address collection,uint256 blockNumber,int256 nftDelta,int256 balanceDelta)"
    );
    bytes32 public constant BALANCE_UPDATES_TYPEHASH =
        keccak256("BalanceUpdates(UserBalanceUpdateData[] updates,uint256 nonce)");
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
    MockLendingManager internal lendingManager; // Changed to MockLendingManager
    ERC4626Vault internal tokenVault;
    IERC20 internal rewardToken; // Actual reward token (DAI)
    MockERC20 internal mockERC20; // Generic mock ERC20 for testing transfers etc.
    MockERC721 internal mockERC721; // Mock NFT Collection 1
    MockERC721 internal mockERC721_2; // Mock NFT Collection 2
    MockCToken internal mockCToken; // Mock cToken for yield simulation
    ProxyAdmin public proxyAdmin;

    function setUp() public virtual {
        uint256 forkId = vm.createFork("mainnet", FORK_BLOCK_NUMBER);
        vm.selectFork(forkId);

        rewardToken = IERC20(DAI_ADDRESS);
        // Removed assignment to non-existent cToken and related require check
        // cToken = CTokenInterface(CDAI_ADDRESS);
        // require(CErc20Interface(CDAI_ADDRESS).underlying() == DAI_ADDRESS, "cToken underlying mismatch");

        vm.startPrank(OWNER);

        rewardsControllerImpl = new RewardsController();
        // Deploy Mocks
        mockERC20 = new MockERC20("Mock Token", "MOCK", 18);
        mockERC721 = new MockERC721("Mock NFT 1", "MNFT1");
        mockERC721_2 = new MockERC721("Mock NFT 2", "MNFT2");
        mockCToken = new MockCToken(address(rewardToken)); // Mock cToken using DAI as underlying
        // Constructor takes only the asset address (rewardToken = DAI)
        lendingManager = new MockLendingManager(address(rewardToken)); // Deploy MockLendingManager

        // Initialize TokenVault with MockLendingManager
        tokenVault = new ERC4626Vault(rewardToken, "Vaulted DAI Test", "vDAIt", OWNER, address(lendingManager));

        vm.stopPrank();
        vm.startPrank(ADMIN);
        proxyAdmin = new ProxyAdmin(ADMIN);
        vm.stopPrank();

        vm.startPrank(OWNER);
        // Proxy deployment and initialization moved down after setting cToken on LM

        // Assertions moved down after rewardsController is initialized

        // Set the mock cToken address *before* initializing RewardsController
        lendingManager.setMockCTokenAddress(address(mockCToken));

        // Now initialize RewardsController, which will call lendingManager.cToken()
        vm.stopPrank(); // Stop OWNER prank before proxy creation/init if needed? Check if init needs OWNER
        vm.startPrank(OWNER); // Ensure OWNER calls initialize via proxy
        bytes memory initData = abi.encodeWithSelector(
            RewardsController.initialize.selector,
            OWNER,
            address(lendingManager),
            address(tokenVault),
            AUTHORIZED_UPDATER
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(rewardsControllerImpl), address(proxyAdmin), initData);
        rewardsController = RewardsController(address(proxy));

        // --- Assertions moved here ---
        address actualUpdater = rewardsController.authorizedUpdater();
        address derivedSignerAddress = vm.addr(UPDATER_PRIVATE_KEY);
        assertEq(actualUpdater, AUTHORIZED_UPDATER, "Authorized updater mismatch after init");
        assertEq(
            derivedSignerAddress, AUTHORIZED_UPDATER, "Mismatch between constant address and derived address from PK"
        );
        // --- End assertions ---

        // Set the rewards controller address *after* it's initialized
        lendingManager.setRewardsController(address(rewardsController));

        // Whitelist the actual mock contract addresses
        rewardsController.addNFTCollection(
            address(mockERC721), BETA_1, IRewardsController.RewardBasis.BORROW, VALID_REWARD_SHARE_PERCENTAGE
        );
        rewardsController.addNFTCollection(
            address(mockERC721_2), BETA_2, IRewardsController.RewardBasis.DEPOSIT, VALID_REWARD_SHARE_PERCENTAGE
        );

        vm.stopPrank();

        uint256 initialFunding = 1_000_000 ether;
        uint256 userFunding = 10_000 ether;
        deal(DAI_ADDRESS, DAI_WHALE, initialFunding * 2);
        deal(address(rewardToken), address(lendingManager), initialFunding); // Fund Mock LM

        vm.startPrank(DAI_WHALE);
        rewardToken.transfer(USER_A, userFunding);
        rewardToken.transfer(USER_B, userFunding);
        rewardToken.transfer(USER_C, userFunding);
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
        // Update labels to reflect actual mock addresses being whitelisted
        vm.label(address(mockERC721), "NFT_COLLECTION_1 (Mock)");
        vm.label(address(mockERC721_2), "NFT_COLLECTION_2 (Mock)");
        vm.label(NFT_COLLECTION_3, "NFT_COLLECTION_3 (Constant, Non-WL)"); // Keep this label distinct if needed
    }

    // --- Helper Functions ---

    // Helper function to calculate domain separator the same way as the contract
    function _buildDomainSeparator() internal view returns (bytes32) {
        // Ensure these match the values used in RewardsController's EIP712 constructor/initializer
        bytes32 typeHashDomain =
            keccak256(bytes("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"));
        bytes32 nameHashDomain = keccak256(bytes("RewardsController")); // Match contract name
        bytes32 versionHashDomain = keccak256(bytes("1")); // Match contract version

        return keccak256(
            abi.encode(typeHashDomain, nameHashDomain, versionHashDomain, block.chainid, address(rewardsController)) // Use proxy address
        );
    }
    // Helper to create hash for BalanceUpdateData array

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

    // Helper to sign UserBalanceUpdates (single user batch)
    function _signUserBalanceUpdates(
        address user,
        IRewardsController.BalanceUpdateData[] memory updates,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 updatesHash = _hashBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(USER_BALANCE_UPDATES_TYPEHASH, user, updatesHash, nonce));
        // Replicate _hashTypedDataV4 logic using the locally built domain separator
        bytes32 domainSeparator = _buildDomainSeparator(); // Use local helper
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // Helper to sign UserBalanceUpdateData array (multi-user batch)
    function _signBalanceUpdates(
        IRewardsController.UserBalanceUpdateData[] memory updates,
        uint256 nonce,
        uint256 privateKey
    ) internal view returns (bytes memory signature) {
        bytes32 updatesHash = _hashUserBalanceUpdates(updates);
        bytes32 structHash = keccak256(abi.encode(BALANCE_UPDATES_TYPEHASH, updatesHash, nonce));
        // Replicate _hashTypedDataV4 logic using the locally built domain separator
        bytes32 domainSeparator = _buildDomainSeparator(); // Use local helper
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        signature = abi.encodePacked(r, s, v);
    }

    // Helper to create hash for UserBalanceUpdateData array
    function _hashUserBalanceUpdates(IRewardsController.UserBalanceUpdateData[] memory updates)
        internal
        pure
        returns (bytes32)
    {
        bytes32[] memory dataHashes = new bytes32[](updates.length);
        for (uint256 i = 0; i < updates.length; i++) {
            dataHashes[i] = keccak256(
                abi.encode(
                    USER_BALANCE_UPDATE_DATA_TYPEHASH,
                    updates[i].user,
                    updates[i].collection,
                    updates[i].blockNumber,
                    updates[i].nftDelta,
                    updates[i].balanceDelta
                )
            );
        }
        return keccak256(abi.encodePacked(dataHashes));
    }

    // Helper to process a single user update for convenience
    function _processSingleUserUpdate(
        address user,
        address collection,
        uint256 blockNum,
        int256 nftDelta,
        int256 balanceDelta
    ) internal {
        uint256 nonce = rewardsController.authorizedUpdaterNonce(AUTHORIZED_UPDATER);
        IRewardsController.BalanceUpdateData[] memory updates = new IRewardsController.BalanceUpdateData[](1);
        updates[0] = IRewardsController.BalanceUpdateData({
            collection: collection,
            blockNumber: blockNum,
            nftDelta: nftDelta,
            balanceDelta: balanceDelta
        });
        bytes memory sig = _signUserBalanceUpdates(user, updates, nonce, UPDATER_PRIVATE_KEY);
        rewardsController.processUserBalanceUpdates(AUTHORIZED_UPDATER, user, updates, sig);
    }
}
