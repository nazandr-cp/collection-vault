// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {SimpleMockCToken} from "../src/mocks/SimpleMockCToken.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {ICollectionsVault} from "../src/interfaces/ICollectionsVault.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

contract CollectionsVaultUnitTest is Test {
    MockERC20 internal asset;
    MockERC721 internal nft;
    SimpleMockCToken internal cToken;
    LendingManager internal lendingManager;
    CollectionsVault internal vault;

    address internal constant OWNER = address(0x1);
    address internal constant ADMIN = address(0x2);

    uint256 internal constant INITIAL_EXCHANGE_RATE = 2e28;

    function setUp() public {
        asset = new MockERC20("Mock Token", "MOCK", 18, 0);
        nft = new MockERC721("MockNFT", "MNFT");
        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(payable(address(this))),
            InterestRateModel(payable(address(this))),
            INITIAL_EXCHANGE_RATE,
            "Mock cToken",
            "mcTOKEN",
            18,
            payable(OWNER)
        );
        lendingManager = new LendingManager(OWNER, address(this), address(asset), address(cToken));
        vault = new CollectionsVault(asset, "Vault", "vMOCK", ADMIN, address(lendingManager));

        vm.startPrank(OWNER);
        lendingManager.revokeVaultRole(address(this));
        lendingManager.grantVaultRole(address(vault));
        vm.stopPrank();
    }

    function _deposit(uint256 amount) internal {
        asset.mint(address(this), amount);
        asset.approve(address(vault), amount);
        vault.depositForCollection(amount, address(this), address(nft));
    }

    function testDepositAndWithdraw() public {
        _deposit(100 ether);
        uint256 shares = vault.balanceOf(address(this));
        assertEq(shares, 100 ether);

        vault.withdrawForCollection(50 ether, address(this), address(this), address(nft));
        assertEq(vault.collectionTotalAssetsDeposited(address(nft)), 50 ether);
        assertEq(vault.balanceOf(address(this)), 50 ether);
    }

    function testWithdrawMoreThanBalanceReverts() public {
        _deposit(10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(
                ICollectionsVault.CollectionInsufficientBalance.selector, address(nft), 20 ether, 10 ether
            )
        );
        vault.withdrawForCollection(20 ether, address(this), address(this), address(nft));
    }

    function testPausePreventsDeposits() public {
        vm.prank(ADMIN);
        vault.pause();
        asset.mint(address(this), 1 ether);
        asset.approve(address(vault), 1 ether);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.depositForCollection(1 ether, address(this), address(nft));
    }

    function testFuzzDepositWithdraw(uint256 amount) public {
        amount = bound(amount, 1, 1e18);
        _deposit(amount);
        uint256 shares = vault.balanceOf(address(this));
        vault.withdrawForCollection(amount, address(this), address(this), address(nft));
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(shares, amount);
    }

    function testDepositZeroNoShares() public {
        vault.depositForCollection(0, address(this), address(nft));
        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.collectionTotalAssetsDeposited(address(nft)), 0);
    }

    function testWithdrawWhilePaused() public {
        _deposit(1 ether);
        vm.prank(ADMIN);
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdrawForCollection(1 ether, address(this), address(this), address(nft));
    }

    function testMultipleCollectionDeposits() public {
        MockERC721 nft2 = new MockERC721("Other", "OTH");
        asset.mint(address(this), 80 ether);
        asset.approve(address(vault), 80 ether);
        vault.depositForCollection(50 ether, address(this), address(nft));
        vault.depositForCollection(30 ether, address(this), address(nft2));

        assertEq(vault.collectionTotalAssetsDeposited(address(nft)), 50 ether);
        assertEq(vault.collectionTotalAssetsDeposited(address(nft2)), 30 ether);
        assertEq(vault.totalSupply(), 80 ether);
    }
}
