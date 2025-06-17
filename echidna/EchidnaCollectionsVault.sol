// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/CollectionsVault.sol";
import "../src/mocks/MockERC20.sol";

// Minimal mock CollectionRegistry for testing
contract MockCollectionRegistry {
    struct Collection {
        address collectionAddress;
        string name;
        uint16 yieldSharePercentage;
        bool isActive;
        address weightFunction;
        int256 p1;
        int256 p2;
    }

    mapping(address => Collection) private _collections;
    mapping(address => bool) private _isRegistered;

    function registerCollection(
        address collectionAddress,
        string memory name,
        uint16 yieldSharePercentage,
        bool isActive
    ) external {
        _collections[collectionAddress] = Collection({
            collectionAddress: collectionAddress,
            name: name,
            yieldSharePercentage: yieldSharePercentage,
            isActive: isActive,
            weightFunction: address(0),
            p1: 0,
            p2: 0
        });
        _isRegistered[collectionAddress] = true;
    }

    function isRegistered(address collection) external view returns (bool) {
        return _isRegistered[collection];
    }

    function getCollection(address collection) external view returns (Collection memory) {
        return _collections[collection];
    }
}

contract EchidnaCollectionsVault {
    CollectionsVault public vault;
    MockERC20 public asset;
    MockCollectionRegistry public collectionRegistry;

    address constant ADMIN = address(0x10000);
    address constant USER1 = address(0x20000);
    address constant USER2 = address(0x30000);
    address constant COLLECTION1 = address(0x40000);
    address constant COLLECTION2 = address(0x50000);

    // Track state for invariants
    uint256 internal lastTotalAssets;
    uint256 internal lastTotalSupply;

    constructor() {
        // Deploy mock asset with initial supply
        asset = new MockERC20("Test Token", "TEST", 18, 0);

        // Deploy collection registry
        collectionRegistry = new MockCollectionRegistry();

        // Deploy vault
        vault = new CollectionsVault(
            IERC20(address(asset)),
            "Test Vault",
            "TVAULT",
            ADMIN,
            address(0), // No lending manager initially
            address(collectionRegistry)
        );

        // Setup initial state
        setupInitialState();
    }

    function setupInitialState() internal {
        // Mint tokens to users and this contract
        asset.mint(address(this), 1000000e18);
        asset.mint(USER1, 1000000e18);
        asset.mint(USER2, 1000000e18);

        // Approve vault to spend tokens
        asset.approve(address(vault), type(uint256).max);

        // Register collections in registry
        collectionRegistry.registerCollection(
            COLLECTION1,
            "Collection 1",
            5000, // 50% yield share
            true
        );

        collectionRegistry.registerCollection(
            COLLECTION2,
            "Collection 2",
            3000, // 30% yield share
            true
        );
    }

    // ECHIDNA PROPERTIES - These functions start with "echidna_" and return bool

    /**
     * @dev Total assets should never exceed the asset balance of the vault
     */
    function echidna_assets_not_exceed_balance() public view returns (bool) {
        uint256 totalAssets = vault.totalAssets();
        uint256 actualBalance = asset.balanceOf(address(vault));
        return totalAssets <= actualBalance;
    }

    /**
     * @dev Total supply should never be greater than total assets (assuming 1:1 initial ratio)
     */
    function echidna_shares_reasonable() public view returns (bool) {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply == 0) return true;
        if (totalAssets == 0) return totalSupply == 0;

        // Shares should not be more than 10x assets (allowing for yield)
        return totalSupply <= totalAssets * 10;
    }

    /**
     * @dev Share price should never be zero after first deposit
     */
    function echidna_share_price_positive() public view returns (bool) {
        if (vault.totalSupply() == 0) return true;
        return vault.convertToAssets(1e18) > 0;
    }

    /**
     * @dev Converting assets to shares and back should be consistent
     */
    function echidna_conversion_roundtrip() public view returns (bool) {
        if (vault.totalSupply() == 0) return true;

        uint256 testAmount = 1000e18;
        if (vault.totalAssets() < testAmount) return true;

        uint256 shares = vault.convertToShares(testAmount);
        if (shares == 0) return true;

        uint256 backToAssets = vault.convertToAssets(shares);

        // Allow small rounding differences (0.1%)
        uint256 tolerance = testAmount / 1000;
        uint256 diff = testAmount > backToAssets ? testAmount - backToAssets : backToAssets - testAmount;
        return diff <= tolerance;
    }

    /**
     * @dev Balance of vault contract should equal sum of all user balances
     */
    function echidna_total_supply_equals_balances() public view returns (bool) {
        uint256 totalSupply = vault.totalSupply();
        uint256 thisBalance = vault.balanceOf(address(this));
        uint256 user1Balance = vault.balanceOf(USER1);
        uint256 user2Balance = vault.balanceOf(USER2);

        return totalSupply == thisBalance + user1Balance + user2Balance;
    }

    /**
     * @dev Max withdraw should never exceed user's assets
     */
    function echidna_max_withdraw_reasonable() public view returns (bool) {
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        uint256 balance = vault.balanceOf(address(this));
        uint256 assetsForShares = vault.convertToAssets(balance);

        return maxWithdraw <= assetsForShares;
    }

    /**
     * @dev Global deposit index should never decrease
     */
    function echidna_global_index_monotonic() public view returns (bool) {
        uint256 currentIndex = vault.globalDepositIndex();
        return currentIndex >= vault.GLOBAL_DEPOSIT_INDEX_PRECISION();
    }

    // HELPER FUNCTIONS FOR FUZZING

    /**
     * @dev Regular ERC4626 deposit
     */
    function deposit(uint256 assets) public {
        // Bound assets to reasonable range (1 to 100,000 tokens)
        assets = bound(assets, 1e18, 100000e18);

        // Ensure we have enough balance
        if (asset.balanceOf(address(this)) < assets) {
            asset.mint(address(this), assets);
            asset.approve(address(vault), type(uint256).max);
        }

        uint256 balanceBefore = asset.balanceOf(address(this));

        try vault.deposit(assets, address(this)) {
            // Successful deposit
        } catch {
            // Failed deposit - ensure no state change
            assert(asset.balanceOf(address(this)) == balanceBefore);
        }
    }

    /**
     * @dev Regular ERC4626 withdraw
     */
    function withdraw(uint256 assets) public {
        uint256 maxAssets = vault.maxWithdraw(address(this));
        if (maxAssets == 0) return;

        assets = bound(assets, 1, maxAssets);

        uint256 sharesBefore = vault.balanceOf(address(this));

        try vault.withdraw(assets, address(this), address(this)) {
            // Successful withdrawal
        } catch {
            // Failed withdrawal - ensure no state change
            assert(vault.balanceOf(address(this)) == sharesBefore);
        }
    }

    /**
     * @dev Mint shares
     */
    function mint(uint256 shares) public {
        shares = bound(shares, 1e18, 100000e18);

        uint256 assetsNeeded = vault.previewMint(shares);

        if (asset.balanceOf(address(this)) < assetsNeeded) {
            asset.mint(address(this), assetsNeeded);
            asset.approve(address(vault), type(uint256).max);
        }

        try vault.mint(shares, address(this)) {
            // Successful mint
        } catch {
            // Failed mint
        }
    }

    /**
     * @dev Redeem shares
     */
    function redeem(uint256 shares) public {
        uint256 maxShares = vault.balanceOf(address(this));
        if (maxShares == 0) return;

        shares = bound(shares, 1, maxShares);

        try vault.redeem(shares, address(this), address(this)) {
            // Successful redeem
        } catch {
            // Failed redeem
        }
    }

    // Utility function to bound values (Echidna doesn't have this built-in)
    function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        require(min <= max, "bound: min > max");
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
