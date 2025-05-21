// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {RewardsController} from "src/RewardsController.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICollectionsVault} from "src/interfaces/ICollectionsVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ILendingManager} from "src/interfaces/ILendingManager.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Define the Collection struct as used by ICollectionsVault interface for the mock
struct Collection {
    address id;
    uint256 itemsCount;
    bool isActive;
}
// Add other fields if the actual struct has them and they are needed by other mock functions.
// For getCollection, these are sufficient based on the mock's return statement.

// Minimal Mock ERC20 for testing
contract MockERC20 is IERC20 {
    string public name = "Mock Token";
    string public symbol = "MTK";
    uint8 public decimals = 18;
    uint256 public totalSupply = 1_000_000 * 10 ** 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
    // Implement other IERC20 functions if needed, or leave as stubs if not called
    // For this test, only balanceOf might be relevant for the RewardsController initialization if it checks balance
}

// Minimal Mock CollectionsVault for testing
// ICollectionsVault already inherits from IERC4626, so no need to list IERC4626 again.
contract MockCollectionsVault is ICollectionsVault {
    address private _asset;

    constructor(address assetToken) {
        _asset = assetToken;
    }

    // --- IERC4626 ---
    function asset() external view override returns (address assetTokenAddress) {
        return _asset;
    }
    // Implement other IERC4626 functions as stubs or with minimal logic if needed

    function totalAssets() external view override returns (uint256 totalManagedAssets) {
        return 0;
    }

    function convertToShares(uint256 assets) external view override returns (uint256 shares) {
        return assets;
    }

    function convertToAssets(uint256 shares) external view override returns (uint256 assets) {
        return shares;
    }

    function maxDeposit(address) external view override returns (uint256 maxAssets) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external view override returns (uint256 shares) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external override returns (uint256 shares) {
        return assets;
    }

    function maxMint(address) external view override returns (uint256 maxShares) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external view override returns (uint256 assets) {
        return shares;
    }

    function mint(uint256 shares, address receiver) external override returns (uint256 assets) {
        return shares;
    }

    function maxWithdraw(address owner) external view override returns (uint256 maxAssets) {
        return this.balanceOf(owner);
    }

    function previewWithdraw(uint256 assets) external view override returns (uint256 shares) {
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares) {
        return assets;
    }

    function maxRedeem(address owner) external view override returns (uint256 maxShares) {
        return this.balanceOf(owner);
    }

    function previewRedeem(uint256 shares) external view override returns (uint256 assets) {
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets) {
        return shares;
    }

    function totalSupply() external view override returns (uint256) {
        return 0;
    } // From IERC20, but IERC4626 is also ERC20-like

    function balanceOf(address account) external view override returns (uint256) {
        return 0;
    } // From IERC20

    function allowance(address owner, address spender) external view override returns (uint256) {
        return 0;
    } // From IERC20

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return true;
    } // From IERC20

    function approve(address spender, uint256 amount) external override returns (bool) {
        return true;
    } // From IERC20

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        return true;
    } // From IERC20

    // --- IERC20Metadata (from IERC4626) ---
    function name() external view override returns (string memory) {
        return "Mock Vault Token";
    }

    function symbol() external view override returns (string memory) {
        return "MVT";
    }

    function decimals() external view override returns (uint8) {
        return 18;
    }

    // --- ICollectionsVault specific (required by interface) ---
    function ADMIN_ROLE() external view override returns (bytes32) {
        return keccak256("ADMIN_ROLE");
    }

    function REWARDS_CONTROLLER_ROLE() external view override returns (bytes32) {
        return keccak256("REWARDS_CONTROLLER_ROLE");
    }

    function lendingManager() external view override returns (ILendingManager) {
        return ILendingManager(address(0)); // Return a dummy ILendingManager
    }

    function collectionTotalAssetsDeposited(address /*collectionAddress*/ ) external view override returns (uint256) {
        return 0;
    }

    function setLendingManager(address /*_lendingManagerAddress*/ ) external override {}

    function setRewardsControllerRole(address /*newRewardsController*/ ) external override {}

    function depositForCollection(uint256 assets, address, /*receiver*/ address /*collectionAddress*/ )
        external
        override
        returns (uint256 shares)
    {
        return assets; // Simple mock: shares = assets
    }

    function mintForCollection(uint256 shares, address, /*receiver*/ address /*collectionAddress*/ )
        external
        override
        returns (uint256 assets)
    {
        return shares; // Simple mock: assets = shares
    }

    function withdrawForCollection(
        uint256 assets,
        address, /*receiver*/
        address, /*owner*/
        address /*collectionAddress*/
    ) external override returns (uint256 shares) {
        return assets; // Simple mock: shares = assets
    }

    function redeemForCollection(
        uint256 shares,
        address, /*receiver*/
        address, /*owner*/
        address /*collectionAddress*/
    ) external override returns (uint256 assets) {
        return shares; // Simple mock: assets = shares
    }

    function transferYieldBatch(
        address[] calldata, /*collections*/
        uint256[] calldata, /*amounts*/
        uint256, /*totalAmount*/
        address /*recipient*/
    ) external override {}

    function collectionYieldTransferred(address /*collectionAddress*/ ) external view override returns (uint256) {
        return 0;
    }

    function setCollectionRewardSharePercentage(address, /*collectionAddress*/ uint16 /*percentage*/ )
        external
        override
    {}

    // --- Potentially custom/old functions (not overriding ICollectionsVault) ---
    function addCollection(address, uint256[] calldata, address) external {}
    function removeCollection(address, uint256[] calldata, address) external {}
    function updateCollectionItems(address, uint256[] calldata, uint256[] calldata, address) external {}

    function getCollection(address) external view returns (Collection memory) {
        return Collection({id: address(0), itemsCount: 0, isActive: false});
    }

    function getCollectionItems(address) external view returns (uint256[] memory) {
        uint256[] memory empty;
        return empty;
    }

    function isCollectionActive(address) external view returns (bool) {
        return true;
    }

    function getCollectionOwner(address) external view returns (address) {
        return address(0);
    }

    function getCollectionItemsWithOwner(address, address) external view returns (uint256[] memory) {
        uint256[] memory empty;
        return empty;
    }

    function getCollectionsByOwner(address) external view returns (address[] memory) {
        address[] memory emptyArr;
        return emptyArr;
    }

    function totalCollections() external view returns (uint256) {
        return 0;
    }

    function version() external pure returns (string memory) {
        // Cannot be override if not in interface
        return "MockVault 1.0";
    }
}

/**
 * @title OwnershipTests
 * @dev This is a simplified version of the Admin tests focusing only on ownership functionality
 * to bypass compilation issues with mock contracts
 */
contract OwnershipTests is Test {
    // Constants
    address constant ADMIN = address(0xAD01);
    address constant USER_1 = address(0xAAA);
    address constant USER_2 = address(0xBBB);
    address constant UPDATER = address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8);

    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Contracts
    RewardsController public rewardsController;

    function setUp() public {
        // Deploy implementation
        RewardsController implementation = new RewardsController(address(1)); // Provide a dummy address for priceOracleAddress_

        // Deploy proxy admin
        // Standard OZ ProxyAdmin constructor takes no arguments.
        // The deployer (this test contract) will be the owner of proxyAdmin.
        ProxyAdmin proxyAdmin = new ProxyAdmin(address(this));
        // If ADMIN needs to be the owner of proxyAdmin, it should be transferred or deployed with vm.prank(ADMIN).
        // For the proxy deployment itself, address(proxyAdmin) is what matters.

        // Deploy Mocks
        MockERC20 mockAssetToken = new MockERC20();
        MockCollectionsVault mockVault = new MockCollectionsVault(address(mockAssetToken));

        // Encode initialization data
        // RewardsController.initialize expects (address initialOwner, ICollectionsVault vaultAddress_, address initialClaimSigner)
        address mockClaimSigner = UPDATER; // Using UPDATER as a placeholder for claimSigner

        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address)",
            ADMIN, // initialOwner
            address(mockVault), // vaultAddress_
            mockClaimSigner // initialClaimSigner
        );

        // Deploy proxy
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(proxyAdmin), initData);

        // Cast proxy to RewardsController
        rewardsController = RewardsController(payable(address(proxy)));
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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER_1));
        rewardsController.transferOwnership(USER_2);
    }

    function test_TransferOwnership_RevertsIfNewOwnerIsZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
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
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, USER_1));
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
}
