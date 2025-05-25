// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {ICollectionsVault} from "./interfaces/ICollectionsVault.sol";

contract CollectionsVault is ERC4626, ICollectionsVault, AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");

    ILendingManager public lendingManager;
    mapping(address => uint256) public collectionTotalAssetsDeposited;
    mapping(address => uint256) public collectionYieldTransferred;
    mapping(address => uint16) public collectionRewardSharePercentage;

    event CollectionYieldTransferred(address indexed collection, uint256 amount);

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManagerAddress // Can be address(0) initially
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        if (address(_asset) == address(0)) revert AddressZero(); // Asset must be valid
        if (initialAdmin == address(0)) revert AddressZero(); // Admin must be valid

        // If a lendingManagerAddress is provided at construction, validate and set it.
        // Otherwise, it's expected to be set later via setLendingManager().
        if (_lendingManagerAddress != address(0)) {
            ILendingManager tempLendingManager = ILendingManager(_lendingManagerAddress);
            // Ensure the provided lending manager's asset matches this vault's asset.
            if (address(tempLendingManager.asset()) != address(_asset)) {
                revert LendingManagerMismatch();
            }
            lendingManager = tempLendingManager;
        }

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
    }

    function setLendingManager(address _lendingManagerAddress) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (_lendingManagerAddress == address(0)) revert AddressZero();
        address oldLendingManagerAddress = address(lendingManager);
        lendingManager = ILendingManager(_lendingManagerAddress);
        if (address(lendingManager.asset()) != address(asset())) {
            revert LendingManagerMismatch();
        }

        IERC20 assetToken = IERC20(asset());
        if (oldLendingManagerAddress != address(0)) {
            assetToken.forceApprove(oldLendingManagerAddress, 0);
        }
        assetToken.forceApprove(_lendingManagerAddress, type(uint256).max);

        emit LendingManagerChanged(oldLendingManagerAddress, _lendingManagerAddress, _msgSender());
    }

    function setRewardsControllerRole(address newRewardsController) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (newRewardsController == address(0)) revert AddressZero();
        _grantRole(REWARDS_CONTROLLER_ROLE, newRewardsController);
    }

    function setCollectionRewardSharePercentage(address collectionAddress, uint16 percentage)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        if (collectionAddress == address(0)) revert AddressZero();
        collectionRewardSharePercentage[collectionAddress] = percentage;
    }

    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        return super.totalAssets() + lendingManager.totalAssets();
    }

    function deposit(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("depositForCollection");
    }

    function depositForCollection(uint256 assets, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, msg.sender, receiver, assets, shares);
    }

    function mint(uint256, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("mintForCollection");
    }

    function mintForCollection(uint256 shares, address receiver, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256, address, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("withdrawForCollection");
    }

    function withdrawForCollection(uint256 assets, address receiver, address owner, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 shares)
    {
        uint256 collectionBalance = collectionTotalAssetsDeposited[collectionAddress];
        if (assets > collectionBalance) {
            revert CollectionInsufficientBalance(collectionAddress, assets, collectionBalance);
        }
        shares = previewWithdraw(assets);
        _hookWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        collectionTotalAssetsDeposited[collectionAddress] = collectionBalance - assets;
        emit CollectionWithdraw(collectionAddress, msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256, address, address) public virtual override(ERC4626, IERC4626) returns (uint256) {
        revert FunctionDisabledUse("redeemForCollection");
    }

    function redeemForCollection(uint256 shares, address receiver, address owner, address collectionAddress)
        public
        virtual
        nonReentrant
        whenNotPaused
        returns (uint256 assets)
    {
        uint256 _totalSupply = totalSupply();
        assets = previewRedeem(shares);
        if (assets == 0) {
            require(shares == 0, "ERC4626: redeem rounds down to zero assets");
        }
        uint256 collectionBalance = collectionTotalAssetsDeposited[collectionAddress];
        _hookWithdraw(assets);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        emit Transfer(owner, address(0), shares);
        uint256 finalAssetsToTransfer = assets;
        bool isFullRedeem = (shares == _totalSupply && shares != 0);
        if (isFullRedeem) {
            uint256 remainingDustInLM = lendingManager.totalAssets();
            if (remainingDustInLM > 0) {
                uint256 redeemedDust = lendingManager.redeemAllCTokens(address(this));
                finalAssetsToTransfer += redeemedDust;
            }
        }
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        if (vaultBalance < finalAssetsToTransfer) {
            revert Vault_InsufficientBalancePostLMWithdraw();
        }
        SafeERC20.safeTransfer(IERC20(asset()), receiver, finalAssetsToTransfer);
        emit Withdraw(msg.sender, receiver, owner, finalAssetsToTransfer, shares);
        collectionTotalAssetsDeposited[collectionAddress] = collectionBalance - assets;
        emit CollectionWithdraw(collectionAddress, msg.sender, receiver, owner, assets, shares);
        return finalAssetsToTransfer;
    }

    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            IERC20 assetToken = IERC20(asset());
            assetToken.forceApprove(address(lendingManager), assets);
            bool success = lendingManager.depositToLendingProtocol(assets);
            assetToken.forceApprove(address(lendingManager), 0);
            if (!success) revert LendingManagerDepositFailed();
        }
    }

    function _hookWithdraw(uint256 assets) internal virtual {
        if (assets == 0) return;
        IERC20 assetToken = IERC20(asset());
        uint256 directBalance = assetToken.balanceOf(address(this));
        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance;
            uint256 availableInLM = lendingManager.totalAssets();
            if (neededFromLM <= availableInLM) {
                if (neededFromLM > 0) {
                    bool success = lendingManager.withdrawFromLendingProtocol(neededFromLM);
                    if (!success) revert LendingManagerWithdrawFailed();
                    uint256 balanceAfterLMWithdraw = assetToken.balanceOf(address(this));
                    if (balanceAfterLMWithdraw < assets) {
                        revert Vault_InsufficientBalancePostLMWithdraw();
                    }
                }
            }
        }
    }

    /**
     * @notice Validates if a yield redemption amount for a collection is within allowed limits
     * @dev Ensures the amount doesn't exceed the collection's share of available yield
     * @param collection The collection address
     * @param requestedAmount The amount being requested
     * @return isValid Whether the requested amount is valid
     * @return maxAllowed The maximum allowed amount for this collection
     */
    function _validateYieldAmount(address collection, uint256 requestedAmount)
        internal
        view
        returns (bool isValid, uint256 maxAllowed)
    {
        // Get collection's reward share percentage (out of 10000)
        uint16 rewardSharePercentage = collectionRewardSharePercentage[collection];

        // If percentage is 0, collection can't claim any yield
        if (rewardSharePercentage == 0) {
            return (requestedAmount == 0, 0);
        }

        // Calculate total available yield in the system (totalAssets - totalPrincipal)
        uint256 totalPrincipal = lendingManager.totalPrincipalDeposited();
        uint256 lmTotalAssets = lendingManager.totalAssets();

        // Calculate total yield available (can't be negative)
        uint256 totalYield = lmTotalAssets > totalPrincipal ? lmTotalAssets - totalPrincipal : 0;

        // Calculate collection's max allowed share of yield
        uint256 collectionYieldShare = (totalYield * rewardSharePercentage) / 10000;

        // Account for yield already transferred to this collection
        uint256 alreadyTransferred = collectionYieldTransferred[collection];
        maxAllowed = collectionYieldShare > alreadyTransferred ? collectionYieldShare - alreadyTransferred : 0;

        return (requestedAmount <= maxAllowed, maxAllowed);
    }

    /**
     * @notice Transfer accrued base yield for multiple collections in a single batch to a recipient.
     * @param collections Array of collection addresses (for logging/tracking, not used in core logic).
     * @param amounts Array of yield token amounts to transfer per collection.
     * @param totalAmount The total sum of amounts to transfer.
     * @param recipient Recipient address.
     */
    function transferYieldBatch(
        address[] calldata collections,
        uint256[] calldata amounts,
        uint256 totalAmount,
        address recipient
    ) external onlyRole(REWARDS_CONTROLLER_ROLE) whenNotPaused {
        if (collections.length != amounts.length) {
            revert FunctionDisabledUse("transferYieldBatch");
        }

        // Validate that we have sufficient balance for the entire batch transfer
        uint256 availableBalance = IERC20(asset()).balanceOf(address(this));
        if (availableBalance < totalAmount) {
            revert CollectionInsufficientBalance(
                address(0), // Using address(0) to indicate this is for the entire batch
                totalAmount,
                availableBalance
            );
        }

        // Validate the amounts sum up to totalAmount
        uint256 calculatedTotal = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            calculatedTotal += amounts[i];
        }
        require(calculatedTotal == totalAmount, "Amounts sum mismatch");

        // Validate and update collection balances without transferring assets yet
        for (uint256 i = 0; i < collections.length; i++) {
            address collection = collections[i];
            uint256 amount = amounts[i];

            // Skip collections with zero amount
            if (amount == 0) continue;

            // Validate the yield amount doesn't exceed collection's allowed share
            (bool isValidAmount, uint256 maxAllowed) = _validateYieldAmount(collection, amount);
            if (!isValidAmount) {
                revert ExcessiveYieldAmount(collection, amount, maxAllowed);
            }

            // Update collection yield tracking
            collectionYieldTransferred[collection] += amount;
            collectionTotalAssetsDeposited[collection] -= amount;

            // Emit an event for this collection's yield transfer
            emit CollectionYieldTransferred(collection, amount);
        }

        // Perform a single transfer for the total amount
        if (totalAmount > 0) {
            // Use the internal function to redeem and transfer yield
            _redeemYieldFromLandingManager(recipient, totalAmount);

            // Emit a batch transfer event
            emit YieldBatchTransferred(totalAmount, recipient);
        }
    }

    function _redeemYieldFromLandingManager(address recipient, uint256 amount) internal {
        if (recipient == address(0)) revert AddressZero();
        if (amount == 0) return;

        // Determine how much we need to withdraw from the lending manager
        IERC20 assetToken = IERC20(asset());
        uint256 vaultBalance = assetToken.balanceOf(address(this));

        // If we don't have enough in the vault, we need to redeem from the lending manager
        if (vaultBalance < amount) {
            uint256 amountToRedeem = amount - vaultBalance;

            // Make sure the lending manager has enough assets
            uint256 availableInLM = lendingManager.totalAssets();
            if (availableInLM < amountToRedeem) {
                revert InsufficientBalanceInProtocol();
            }

            // Withdraw from lending manager
            bool success = lendingManager.withdrawFromLendingProtocol(amountToRedeem);
            if (!success) revert LendingManagerWithdrawFailed();

            // Verify we have enough balance after withdrawal
            uint256 balanceAfterWithdraw = assetToken.balanceOf(address(this));
            if (balanceAfterWithdraw < amount) {
                revert Vault_InsufficientBalancePostLMWithdraw();
            }
        }

        // Transfer assets to recipient
        assetToken.safeTransfer(recipient, amount);
    }

    // --- Pausable Functions ---

    /**
     * @notice Pauses the contract.
     * @dev This function can only be called by an address with the ADMIN_ROLE.
     * All pausable functions will revert when the contract is paused.
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev This function can only be called by an address with the ADMIN_ROLE.
     * All pausable functions will resume normal operation when unpaused.
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
