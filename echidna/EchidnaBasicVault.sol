// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/mocks/MockERC20.sol";
import "../src/CollectionsVault.sol";

// Simple mock CollectionRegistry for basic testing
contract SimpleCollectionRegistry {
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

    function isRegistered(address collection) external view returns (bool) {
        return _isRegistered[collection];
    }

    function getCollection(address collection) external view returns (Collection memory) {
        return _collections[collection];
    }

    // Simple setup for basic testing
    function setup() external {
        _collections[address(0x1234)] = Collection({
            collectionAddress: address(0x1234),
            name: "Test Collection",
            yieldSharePercentage: 1000, // 10%
            isActive: true,
            weightFunction: address(0),
            p1: 0,
            p2: 0
        });
        _isRegistered[address(0x1234)] = true;
    }
}

contract EchidnaBasicVault {
    CollectionsVault public vault;
    MockERC20 public asset;
    SimpleCollectionRegistry public registry;

    address constant ADMIN = address(0x1000);

    constructor() {
        // Deploy asset with initial supply
        asset = new MockERC20("Test Asset", "TST", 18, 0);

        // Deploy simple registry
        registry = new SimpleCollectionRegistry();
        registry.setup();

        // Deploy vault
        vault =
            new CollectionsVault(IERC20(address(asset)), "Test Vault", "TVAULT", ADMIN, address(0), address(registry));

        // Mint tokens and approve
        asset.mint(address(this), 1000000e18);
        asset.approve(address(vault), type(uint256).max);
    }

    // ECHIDNA PROPERTIES

    function echidna_total_assets_never_exceeds_balance() public view returns (bool) {
        return vault.totalAssets() <= asset.balanceOf(address(vault));
    }

    function echidna_total_supply_consistency() public view returns (bool) {
        return vault.totalSupply() == vault.balanceOf(address(this));
    }

    function echidna_share_price_positive() public view returns (bool) {
        if (vault.totalSupply() == 0) return true;
        return vault.convertToAssets(1e18) > 0;
    }

    function echidna_max_withdraw_reasonable() public view returns (bool) {
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        uint256 maxRedeem = vault.maxRedeem(address(this));
        uint256 assetsFromShares = vault.convertToAssets(maxRedeem);

        // Max withdraw should not be greater than assets from max redeem
        return maxWithdraw <= assetsFromShares;
    }

    function echidna_preview_consistency() public view returns (bool) {
        if (vault.totalSupply() == 0) return true;

        uint256 testAssets = 1000e18;
        if (asset.balanceOf(address(this)) < testAssets) return true;

        uint256 previewShares = vault.previewDeposit(testAssets);
        uint256 previewAssets = vault.previewMint(previewShares);

        // Allow small rounding differences
        uint256 diff = testAssets > previewAssets ? testAssets - previewAssets : previewAssets - testAssets;
        return diff <= testAssets / 1000; // 0.1% tolerance
    }

    // FUZZ FUNCTIONS

    function deposit(uint256 assets) public {
        if (assets == 0) return;
        assets = assets % 100000e18 + 1;

        if (asset.balanceOf(address(this)) < assets) {
            asset.mint(address(this), assets);
            asset.approve(address(vault), type(uint256).max);
        }

        try vault.deposit(assets, address(this)) {} catch {}
    }

    function withdraw(uint256 assets) public {
        if (assets == 0) return;
        uint256 maxAssets = vault.maxWithdraw(address(this));
        if (maxAssets == 0) return;

        assets = assets % maxAssets + 1;

        try vault.withdraw(assets, address(this), address(this)) {} catch {}
    }

    function mint(uint256 shares) public {
        if (shares == 0) return;
        shares = shares % 100000e18 + 1;

        uint256 assetsNeeded = vault.previewMint(shares);
        if (asset.balanceOf(address(this)) < assetsNeeded) {
            asset.mint(address(this), assetsNeeded);
            asset.approve(address(vault), type(uint256).max);
        }

        try vault.mint(shares, address(this)) {} catch {}
    }

    function redeem(uint256 shares) public {
        if (shares == 0) return;
        uint256 maxShares = vault.balanceOf(address(this));
        if (maxShares == 0) return;

        shares = shares % maxShares + 1;

        try vault.redeem(shares, address(this), address(this)) {} catch {}
    }
}
