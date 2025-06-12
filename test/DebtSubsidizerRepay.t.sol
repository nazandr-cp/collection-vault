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
import {IDebtSubsidizer} from "../src/interfaces/IDebtSubsidizer.sol";
import {ICollectionsVault} from "../src/interfaces/ICollectionsVault.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DebtSubsidizerRepayTest is Test {
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
        vm.startPrank(OWNER);
        epochManager.grantVaultRole(address(vault));
        vm.stopPrank();
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

    function _domainSeparator() internal view returns (bytes32) {
        bytes32 typeHash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 nameHash = keccak256(bytes("DebtSubsidizer"));
        bytes32 versionHash = keccak256(bytes("1"));
        return keccak256(abi.encode(typeHash, nameHash, versionHash, block.chainid, address(debtSubsidizer)));
    }

    function _signSubsidies(IDebtSubsidizer.Subsidy[] memory subsidies) internal view returns (bytes memory) {
        bytes32 subsidiesHash = keccak256(abi.encode(subsidies));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), subsidiesHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    function testRepayBorrowBehalfViaSubsidizer() public {
        vm.startPrank(BORROWER);
        cToken.borrow(40 ether);
        vm.stopPrank();

        _generateYield(100 ether);

        IDebtSubsidizer.Subsidy[] memory subsidies = new IDebtSubsidizer.Subsidy[](1);
        subsidies[0] = IDebtSubsidizer.Subsidy({
            account: BORROWER,
            collection: address(nft),
            vault: address(vault),
            amount: 20 ether,
            nonce: 0,
            deadline: block.timestamp + 1 days
        });
        bytes memory sig = _signSubsidies(subsidies);

        uint256 balBefore = cToken.borrowBalanceStored(BORROWER);
        uint256 yieldBefore = vault.collectionYieldTransferred(address(nft));

        vm.recordLogs();
        vm.expectRevert(
            abi.encodeWithSelector(ICollectionsVault.ExcessiveYieldAmount.selector, address(nft), 20 ether, 0)
        );
        debtSubsidizer.subsidize(address(vault), subsidies, sig);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        uint256 balAfter = cToken.borrowBalanceStored(BORROWER);
        uint256 yieldAfter = vault.collectionYieldTransferred(address(nft));
        assertEq(balAfter, balBefore, "borrow balance should be unchanged");
        assertEq(yieldAfter, yieldBefore, "yield should be unchanged");

        bytes32 subsidyTopic = keccak256("DebtSubsidized(address,address,address,uint256)");
        bool subsidyFound;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == subsidyTopic) {
                subsidyFound = true;
            }
        }
        assertTrue(subsidyFound, "DebtSubsidized event not emitted");
    }
}
