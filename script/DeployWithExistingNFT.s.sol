// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {CollectionsVault} from "../src/CollectionsVault.sol";
import {EpochManager} from "../src/EpochManager.sol";
import {CollectionRegistry} from "../src/CollectionRegistry.sol";
import {ICollectionRegistry} from "../src/interfaces/ICollectionRegistry.sol";
import {DebtSubsidizer} from "../src/DebtSubsidizer.sol";
import {Roles} from "../src/Roles.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployWithExistingNFT is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address existingNFT = vm.envAddress("NFT_ADDRESS");
        vm.startBroadcast(deployerKey);

        address asset = vm.envAddress("ASSET_ADDRESS");
        address cToken = vm.envAddress("CTOKEN_ADDRESS");
        address admin = vm.envAddress("SENDER");

        LendingManager lendingManager = new LendingManager(admin, admin, asset, cToken);
        CollectionRegistry collectionRegistry = new CollectionRegistry(admin);
        CollectionsVault vault = new CollectionsVault(
            MockERC20(asset), "Vault mUSDC", "vMOCK", admin, address(lendingManager), address(collectionRegistry)
        );
        EpochManager epochManager = new EpochManager(1 days, admin, admin, address(0));
        DebtSubsidizer debtImpl = new DebtSubsidizer();

        bytes memory initData =
            abi.encodeWithSelector(DebtSubsidizer.initialize.selector, admin, address(collectionRegistry));

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(debtImpl), admin, initData);
        DebtSubsidizer debtSubsidizer = DebtSubsidizer(address(proxy));
        collectionRegistry.registerCollection(
            ICollectionRegistry.Collection({
                collectionAddress: existingNFT,
                collectionType: ICollectionRegistry.CollectionType.ERC721,
                weightFunction: ICollectionRegistry.WeightFunction({
                    fnType: ICollectionRegistry.WeightFunctionType.LINEAR,
                    p1: 1.0e18,
                    p2: 0
                }),
                yieldSharePercentage: 5000,
                vaults: new address[](0)
            })
        );

        collectionRegistry.addVaultToCollection(existingNFT, address(vault));
        lendingManager.grantRoleWithDetails(Roles.OPERATOR_ROLE, address(vault));
        address currentEpochManager = address(vault.epochManager());
        if (currentEpochManager == address(0)) {
            vault.setEpochManager(address(epochManager));
        } else if (currentEpochManager != address(epochManager)) {
            vault.setEpochManager(address(epochManager));
        }

        bool hasOperatorRole = vault.hasRole(Roles.OPERATOR_ROLE, admin);
        if (!hasOperatorRole) {
            vault.grantRoleWithDetails(Roles.OPERATOR_ROLE, admin);
        }

        bool vaultHasRoleOnEpochManager = epochManager.hasRole(Roles.OPERATOR_ROLE, address(vault));
        if (!vaultHasRoleOnEpochManager) {
            epochManager.grantRoleWithDetails(Roles.OPERATOR_ROLE, address(vault));
        }
        vault.validateContract(address(lendingManager));
        epochManager.validateContract(address(vault));
        epochManager.validateContract(address(debtSubsidizer));

        debtSubsidizer.addVault(address(vault), address(lendingManager));
        vault.setDebtSubsidizer(address(debtSubsidizer));

        uint256 initialDepositAmount = 100000 * (10 ** MockERC20(asset).decimals());
        vault.grantRole(Roles.COLLECTION_MANAGER_ROLE, admin);
        MockERC20(asset).approve(address(vault), initialDepositAmount);
        vault.depositForCollection(initialDepositAmount, admin, existingNFT);

        vm.stopBroadcast();

        require(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "Admin missing DEFAULT_ADMIN_ROLE on vault");
        require(vault.hasRole(Roles.OWNER_ROLE, admin), "Admin missing OWNER_ROLE on vault");
        require(vault.hasRole(Roles.ADMIN_ROLE, admin), "Admin missing ADMIN_ROLE on vault");
        require(vault.hasRole(Roles.GUARDIAN_ROLE, admin), "Admin missing GUARDIAN_ROLE on vault");
        require(vault.hasRole(Roles.OPERATOR_ROLE, admin), "Admin missing OPERATOR_ROLE on vault");
        require(
            lendingManager.hasRole(Roles.OPERATOR_ROLE, address(vault)), "Vault missing OPERATOR_ROLE on LendingManager"
        );
        require(
            epochManager.hasRole(Roles.OPERATOR_ROLE, address(vault)), "Vault missing OPERATOR_ROLE on EpochManager"
        );
        require(
            collectionRegistry.hasRole(Roles.COLLECTION_MANAGER_ROLE, admin), "Admin missing COLLECTION_MANAGER_ROLE"
        );
        require(
            vault.hasRole(Roles.OPERATOR_ROLE, address(debtSubsidizer)), "DebtSubsidizer missing OPERATOR_ROLE on vault"
        );
        require(vault.isCollectionOperator(existingNFT, admin), "Admin missing collection operator access");
    }
}
