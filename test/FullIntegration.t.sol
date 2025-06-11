// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {SimpleMockCToken} from "../src/mocks/SimpleMockCToken.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {ICollectionsVault} from "../src/interfaces/ICollectionsVault.sol";
import {IDebtSubsidizer} from "../src/interfaces/IDebtSubsidizer.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract FullIntegrationTest is Test {
    MockERC20 internal asset;
    MockERC721 internal nft;
    SimpleMockCToken internal cToken;
    LendingManager internal lendingManager;
    CollectionsVault internal vault;
    EpochManager internal epochManager;
    DebtSubsidizer internal debtSubsidizer;

    address internal constant OWNER = address(0x1);
    address internal constant ADMIN = address(0x2);
    address internal constant AUTOMATION = address(0x3);
    address internal constant BORROWER = address(0xB0B);
    uint256 internal constant SIGNER_PK = uint256(0xdeadbeef);
    address internal SIGNER;

    uint256 internal constant INITIAL_EXCHANGE_RATE = 2e28;

    function setUp() public {
        SIGNER = vm.addr(SIGNER_PK);
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

        epochManager = new EpochManager(1 days, AUTOMATION, OWNER);
        vm.prank(ADMIN);
        vault.setEpochManager(address(epochManager));

        DebtSubsidizer debtImpl = new DebtSubsidizer();
        bytes memory initData = abi.encodeWithSelector(DebtSubsidizer.initialize.selector, OWNER, SIGNER);
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), OWNER, initData);
        debtSubsidizer = DebtSubsidizer(address(proxy));

        vm.prank(OWNER);
        debtSubsidizer.addVault(address(vault), address(lendingManager));

        vm.prank(ADMIN);
        vault.setDebtSubsidizer(address(debtSubsidizer));

        vm.prank(OWNER);
        debtSubsidizer.whitelistCollection(
            address(vault),
            address(nft),
            IDebtSubsidizer.CollectionType.ERC721,
            IDebtSubsidizer.RewardBasis.DEPOSIT,
            5000
        );

        vm.prank(ADMIN);
        vault.setCollectionYieldSharePercentage(address(nft), 5000);

        asset.mint(address(this), 1000 ether);
        asset.approve(address(vault), 1000 ether);
        vault.depositForCollection(1000 ether, address(this), address(nft));
    }

    function _generateYield(uint256 amount) internal {
        asset.mint(address(cToken), amount);
    }

    function testFullSystemLifecycle() public {
        vm.startPrank(BORROWER);
        cToken.borrow(20 ether);
        vm.stopPrank();

        _generateYield(100 ether);
        vm.prank(ADMIN);
        vault.indexCollectionsDeposits();

        vm.prank(AUTOMATION);
        epochManager.startNewEpoch();

        vm.prank(address(vault));
        epochManager.allocateVaultYield(address(vault), 10 ether);

        (IDebtSubsidizer.VaultInfo memory info) = debtSubsidizer.vault(address(vault));
        assertEq(info.lendingManager, address(lendingManager), "vault info LM mismatch");
        bool whitelisted = debtSubsidizer.isCollectionWhitelisted(address(vault), address(nft));
        assertTrue(whitelisted, "collection should be whitelisted");

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(AUTOMATION);
        epochManager.beginEpochProcessing(1);
        vm.prank(AUTOMATION);
        epochManager.finalizeEpoch(1, 0);
        (,,,,, EpochManager.EpochStatus status) = epochManager.getEpochDetails(1);
        assertEq(uint256(status), uint256(EpochManager.EpochStatus.Completed));
    }
}
