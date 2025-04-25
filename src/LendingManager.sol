// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol"; // Import for decimals()
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import "forge-std/console.sol";

/**
 * @title LendingManager (Compound V2 Fork Adapter)
 * @notice Manages deposits and withdrawals to a specific Compound V2 fork cToken market.
 * @dev Implements the `ILendingManager` interface to interact with a designated `cToken` contract.
 *      Utilizes OpenZeppelin's AccessControl for role-based permissions:
 *      - `VAULT_ROLE`: For the associated ERC4626Vault contract.
 *      - `REWARDS_CONTROLLER_ROLE`: For the associated RewardsController contract.
 *      - `ADMIN_ROLE`: For administrative tasks like managing roles.
 */
contract LendingManager is ILendingManager, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    /// @notice Role identifier for the associated ERC4626Vault contract.
    bytes32 public constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");
    /// @notice Role identifier for the associated RewardsController contract.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    /// @notice Role identifier for administrative tasks within this LendingManager.

    IERC20 private immutable _asset;
    uint8 private immutable underlyingDecimals;
    uint8 private immutable cTokenDecimals;

    /**
     * @notice Get the underlying ERC20 asset managed by the lending manager.
     * @return ERC20 asset address.
     */
    function asset() external view override returns (IERC20) {
        return _asset;
    }

    /// @notice The underlying ERC20 asset managed by this contract (e.g., USDC, DAI).
    CErc20Interface internal immutable _cToken;
    /// @notice The corresponding Compound V2 fork cToken contract (e.g., cUSDC, cDAI).

    /**
     * @notice Get the cToken address associated with the underlying asset.
     * @return cToken address.
     */
    function cToken() external view override returns (address) {
        return address(_cToken);
    }

    uint256 public constant R0_BASIS_POINTS = 5;

    /// @notice Example base reward rate (0.05%) used in `getBaseRewardPerBlock` calculation.
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    /// @notice Denominator for basis points calculations (100% = 10,000 basis points).
    uint256 private constant PRECISION = 1e18;
    /// @notice Precision factor (18 decimals) used in reward calculations.

    // Compound V2 Exchange Rate Scale: 1 * 10^(18 + underlyingDecimals - cTokenDecimals)
    // Assuming underlying=18 decimals, cToken=8 decimals: 1 * 10^(18 + 18 - 8) = 1e28
    uint256 private constant EXCHANGE_RATE_SCALE = 1e28;

    uint256 public totalPrincipalDeposited;
    /// @notice Tracks the net amount of underlying assets deposited by the Vault.

    // Note: Role management events (`RoleGranted`, `RoleRevoked`) are emitted by the inherited AccessControl contract.
    /// @notice Emitted when accrued yield (underlying asset) is successfully transferred to a recipient (typically the RewardsController).
    event YieldTransferred(address indexed recipient, uint256 amount);
    /// @notice Emitted when underlying assets are successfully deposited into the cToken contract.
    event DepositToProtocol(address indexed caller, uint256 amount);
    /// @notice Emitted when underlying assets are successfully withdrawn (redeemed) from the cToken contract.
    event WithdrawFromProtocol(address indexed caller, uint256 amount);

    /// @notice Reverts if the underlying cToken `mint` operation returns a non-zero error code.
    error MintFailed();
    /// @notice Reverts if the underlying cToken `redeemUnderlying` operation returns a non-zero error code.
    error RedeemFailed();
    /// @notice Reverts if transferring yield (underlying asset) fails. (Note: SafeERC20 handles reverts on transfer failures, making this potentially redundant).
    error TransferYieldFailed();
    /// @notice Reverts if a critical address (e.g., admin, vault, controller, asset, cToken) is the zero address during deployment or function calls.
    error AddressZero();
    // Note: AccessControl's `AccessControlUnauthorizedAccount` error is used for general role checks, but custom errors below provide more specific context.
    /// @notice Reverts if attempting to withdraw or redeem more underlying assets than this contract currently holds in the cToken market.
    error InsufficientBalanceInProtocol();
    /// @notice Reverts if a function restricted by the `onlyVault` modifier is called by an address lacking the `VAULT_ROLE`.
    error LM_CallerNotVault(address caller);
    /// @notice Reverts if a function restricted by the `onlyRewardsController` modifier is called by an address lacking the `REWARDS_CONTROLLER_ROLE`.
    error LM_CallerNotRewardsController(address caller);
    /// @notice Reverts if attempting to revoke the last admin for a specific role (Note: This check is not implemented in the base AccessControl).
    error CannotRemoveLastAdmin(bytes32 role);

    constructor(
        address initialAdmin,
        address vaultAddress,
        address rewardsControllerAddress,
        address _assetAddress,
        address _cTokenAddress
    ) {
        // Validate constructor arguments: ensure critical addresses are not the zero address.
        if (
            initialAdmin == address(0) || vaultAddress == address(0) || rewardsControllerAddress == address(0)
                || _assetAddress == address(0) || _cTokenAddress == address(0)
        ) {
            revert AddressZero();
        }

        // Set immutable state variables.
        _asset = IERC20(_assetAddress);
        _cToken = CErc20Interface(_cTokenAddress);

        // Fetch and store decimals (assuming they implement IERC20Metadata)
        underlyingDecimals = IERC20Metadata(_assetAddress).decimals();
        cTokenDecimals = IERC20Metadata(_cTokenAddress).decimals();
        // console.log("LM Constructor: Underlying Decimals =", underlyingDecimals); // Removed log
        // console.log("LM Constructor: cToken Decimals =", cTokenDecimals); // Removed log

        // Grant initial roles.
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(VAULT_ROLE, vaultAddress);
        _grantRole(REWARDS_CONTROLLER_ROLE, rewardsControllerAddress);

        // Grant infinite approval to the cToken contract for the underlying asset.
        _asset.approve(address(_cToken), type(uint256).max);
    }

    /// @dev Restricts function execution to addresses holding the `VAULT_ROLE`. Reverts with `LM_CallerNotVault` if check fails.
    modifier onlyVault() {
        if (!hasRole(VAULT_ROLE, msg.sender)) {
            revert LM_CallerNotVault(msg.sender);
        }
        _;
    }

    /// @dev Restricts function execution to addresses holding the `REWARDS_CONTROLLER_ROLE`. Reverts with `LM_CallerNotRewardsController` if check fails.
    modifier onlyRewardsController() {
        if (!hasRole(REWARDS_CONTROLLER_ROLE, msg.sender)) {
            revert LM_CallerNotRewardsController(msg.sender);
        }
        _;
    }

    /**
     * @notice Deposits underlying assets into the Compound V2 fork's cToken market.
     * @dev Restricted to callers with the `VAULT_ROLE`. Pulls `amount` of the `asset` from the caller (`msg.sender`, expected to be the Vault)
     *      using `safeTransferFrom`. Then, mints the corresponding cTokens by calling `cToken.mint(amount)`.
     *      Requires the caller (Vault) to have approved this LendingManager contract to spend its assets.
     * @param amount The amount of the underlying asset to deposit.
     * @return success Boolean indicating whether the deposit was successful (always true if no revert).
     */
    function depositToLendingProtocol(uint256 amount) external override onlyVault returns (bool success) {
        if (amount == 0) return true;

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 mintResult = _cToken.mint(amount);
        if (mintResult != 0) {
            revert MintFailed();
        }

        totalPrincipalDeposited += amount;

        emit DepositToProtocol(msg.sender, amount);
        return true;
    }

    /**
     * @notice Withdraws underlying assets from the Compound V2 fork's cToken market.
     * @dev Restricted to callers with the `VAULT_ROLE`. Redeems `amount` of the underlying `asset` from the cToken market
     *      by calling `cToken.redeemUnderlying(amount)`. The redeemed assets are received by this contract and then
     *      transferred to the caller (`msg.sender`, expected to be the Vault).
     * @param amount The amount of the underlying asset to withdraw.
     * @return success Boolean indicating whether the withdrawal was successful (always true if no revert).
     */
    function withdrawFromLendingProtocol(uint256 amount) external override onlyVault returns (bool success) {
        if (amount == 0) return true;

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult; // Silence compiler warning

        uint256 availableBalance = totalAssets();
        if (availableBalance < amount) {
            revert InsufficientBalanceInProtocol();
        }

        uint256 redeemResult = _cToken.redeemUnderlying(amount);
        if (redeemResult != 0) {
            revert RedeemFailed();
        }

        _asset.safeTransfer(msg.sender, amount);

        // Update total principal tracked
        if (totalPrincipalDeposited >= amount) {
            totalPrincipalDeposited -= amount;
        } else {
            totalPrincipalDeposited = 0;
        }

        emit WithdrawFromProtocol(msg.sender, amount);
        return true;
    }

    /**
     * @notice Calculates the total underlying assets currently held by this contract within the cToken market.
     * @dev Calculates the balance based on this contract's cToken balance and the *stored* exchange rate (`exchangeRateStored()`).
     *      Using the stored rate keeps this function as a `view` (no state change, gas-free call), but the returned value
     *      might be slightly stale if interest has accrued within the current block before the rate was updated by a transaction.
     *      Formula: `underlying = (cTokenBalance * exchangeRateStored) / 1e18`.
     *      The exchange rate is scaled by `1 * 10^(18 + underlyingDecimals - cTokenDecimals)`.
     * @return The total amount of underlying assets held in the cToken market.
     */
    function totalAssets() public view override returns (uint256) {
        uint256 cTokenBalance = CTokenInterface(address(_cToken)).balanceOf(address(this));
        if (cTokenBalance == 0) {
            return 0;
        }

        uint256 exchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        if (exchangeRate == 0) {
            return 0;
        }

        // Formula: assets = (cTokenBalance * exchangeRate) / 1e18
        // Based on observed mainnet cToken behavior, exchangeRateStored() is scaled by 1e18.
        // The formula is: underlying = cTokens * exchangeRateStored / 1e18
        uint256 scaleFactor = 1e18;

        // Formula: underlying = cTokens * scaledExchangeRate / scaleFactor
        uint256 assets = (cTokenBalance * exchangeRate) / scaleFactor;

        // console.log("LM totalAssets:"); // Removed logs
        // console.log("  cTokenBalance:", cTokenBalance);
        // console.log("  exchangeRate (raw):", exchangeRate);
        // console.log("  underlyingDecimals:", underlyingDecimals);
        // console.log("  cTokenDecimals:", cTokenDecimals);
        // console.log("  calculated scaleFactor:", scaleFactor);
        // console.log("  calculated assets:", assets);

        return assets;
    }

    /**
     * @notice Estimate the base reward generated per block based on current total assets and configured rate.
     * @dev Used by RewardsController for reward index calculation. Actual yield may differ due to protocol factors.
     * @return Estimated base reward per block.
     */
    function getBaseRewardPerBlock() external view override returns (uint256) {
        uint256 currentTotalAssets = totalAssets();
        if (currentTotalAssets == 0) {
            return 0;
        }
        return (currentTotalAssets * R0_BASIS_POINTS) / BASIS_POINTS_DENOMINATOR;
    }

    /**
     * @notice Redeem accrued yield from the Compound protocol and transfer to a recipient.
     * @dev Only callable by REWARDS_CONTROLLER_ROLE. Redeems and transfers yield to recipient.
     * @param amount Amount of yield to redeem and transfer.
     * @param recipient Recipient address.
     * @return amountTransferred The actual amount of yield transferred (may be less than requested due to capping).
     */
    function transferYield(uint256 amount, address recipient)
        external
        override
        onlyRewardsController
        returns (uint256 amountTransferred)
    {
        if (amount == 0) return 0;
        if (recipient == address(0)) revert AddressZero();

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult; // Silence compiler warning

        uint256 availableBalance = totalAssets();
        uint256 availableYield =
            (availableBalance > totalPrincipalDeposited) ? availableBalance - totalPrincipalDeposited : 0;

        if (amount > availableYield) {
            amountTransferred = availableYield;
        } else {
            amountTransferred = amount;
        }

        if (amountTransferred == 0) {
            return 0;
        }
        // console.log("LM.transferYield (Before Redeem):"); // Removed log
        // console.log("  Requested Amount:", amount); // Removed log
        // console.log("  Available Balance (totalAssets):", availableBalance); // Removed log
        // console.log("  Total Principal Deposited:", totalPrincipalDeposited); // Removed log
        // console.log("  Calculated Available Yield:", availableYield); // Removed log

        if (amountTransferred == 0) {
            console.log("LM.transferYield: Final amount to transfer (underlying) is 0, skipping redeem/transfer.");
            return 0;
        }

        // --- ADDED CHECK: Calculate cTokens required for the underlying amount --- //
        uint256 exchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        if (exchangeRate == 0) {
            console.log("LM.transferYield Error: Exchange rate is zero.");
            return 0;
        }
        // Formula: cTokens = underlying * 1e18 / exchangeRate
        uint256 cTokensToRedeem = (amountTransferred * 1e18) / exchangeRate;

        if (cTokensToRedeem == 0) {
            console.log(
                "LM.transferYield: Underlying amount %s corresponds to 0 cTokens at rate %s. Skipping redeem/transfer.",
                amountTransferred,
                exchangeRate
            );
            return 0;
        }
        // --- END ADDED CHECK --- //

        // console.log("LM.transferYield: Proceeding with transfer amount:", amountTransferred); // Redundant log

        // --- CHANGE: Use redeem() instead of redeemUnderlying() --- //
        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this)); // Get balance before

        uint256 redeemResult = _cToken.redeem(cTokensToRedeem);
        if (redeemResult != 0) {
            // console.log("LM.transferYield Error: cToken.redeem failed with code:", redeemResult); // Log removed
            revert RedeemFailed();
        }

        uint256 balanceAfterRedeem = _asset.balanceOf(address(this)); // Get balance after

        // Use the actual balance received after redemption for the transfer
        uint256 actualAmountTransferred = balanceAfterRedeem - balanceBeforeRedeem; // Calculate actual received amount

        if (actualAmountTransferred > 0) {
            _asset.safeTransfer(recipient, actualAmountTransferred);
        }

        emit YieldTransferred(recipient, actualAmountTransferred); // Emit the actual amount transferred
        return actualAmountTransferred; // Return the actual amount transferred
    }

    /**
     * @notice Grant REWARDS_CONTROLLER_ROLE to an account.
     * @dev Only callable by ADMIN_ROLE.
     * @param newController Address to grant the role.
     */
    function grantRewardsControllerRole(address newController) external onlyRole(ADMIN_ROLE) {
        if (newController == address(0)) revert AddressZero();
        _grantRole(REWARDS_CONTROLLER_ROLE, newController);
    }

    /**
     * @notice Revoke REWARDS_CONTROLLER_ROLE from an account.
     * @dev Only callable by ADMIN_ROLE.
     * @param controller Address to revoke the role from.
     */
    function revokeRewardsControllerRole(address controller) external onlyRole(ADMIN_ROLE) {
        if (controller == address(0)) revert AddressZero();
        _revokeRole(REWARDS_CONTROLLER_ROLE, controller);
    }

    // --- Administrative Functions for Role Management ---

    /**
     * @notice Grant VAULT_ROLE to an account.
     * @dev Only callable by ADMIN_ROLE.
     * @param newVault Address to grant the role.
     */
    function grantVaultRole(address newVault) external onlyRole(ADMIN_ROLE) {
        if (newVault == address(0)) revert AddressZero();
        _grantRole(VAULT_ROLE, newVault);
    }

    /**
     * @notice Revoke VAULT_ROLE from an account.
     * @dev Only callable by ADMIN_ROLE.
     * @param vault Address to revoke the role from.
     */
    function revokeVaultRole(address vault) external onlyRole(ADMIN_ROLE) {
        if (vault == address(0)) revert AddressZero();
        _revokeRole(VAULT_ROLE, vault);
    }

    /**
     * @notice Grant ADMIN_ROLE to an account.
     * @dev Only callable by ADMIN_ROLE.
     * @param newAdmin Address to grant the role.
     */
    function grantAdminRole(address newAdmin) external onlyRole(ADMIN_ROLE) {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    /**
     * @notice Revoke ADMIN_ROLE from an account.
     * @dev Only callable by ADMIN_ROLE. Does not prevent removing last admin unless using AccessControlEnumerable.
     * @param admin Address to revoke the role from.
     */
    function revokeAdminRole(address admin) external onlyRole(ADMIN_ROLE) {
        if (admin == address(0)) revert AddressZero();
        // Note: Base AccessControl doesn't prevent removing the last admin.
        // Consider AccessControlEnumerable or custom logic if this protection is needed.
        _revokeRole(ADMIN_ROLE, admin);
    }

    /**
     * @notice Grant ADMIN_ROLE as DEFAULT_ADMIN_ROLE.
     * @dev Only callable by DEFAULT_ADMIN_ROLE.
     * @param newAdmin Address to grant the role.
     */
    function grantAdminRoleAsDefaultAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    /**
     * @notice Revoke ADMIN_ROLE as DEFAULT_ADMIN_ROLE.
     * @dev Only callable by DEFAULT_ADMIN_ROLE. Does not prevent removing last admin unless using AccessControlEnumerable.
     * @param admin Address to revoke the role from.
     */
    function revokeAdminRoleAsDefaultAdmin(address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (admin == address(0)) revert AddressZero();
        _revokeRole(ADMIN_ROLE, admin);
    }

    /**
     * @notice Redeems the entire cToken balance held by this LendingManager contract.
     * @dev Restricted to callers with the `VAULT_ROLE`. This is typically used during a full vault redemption
     *      to sweep any remaining dust from the Compound protocol.
     *      Calls `cToken.redeem()` with the full cToken balance of this contract.
     *      Transfers the redeemed underlying assets to the caller (Vault).
     * @param recipient The address to receive the redeemed underlying assets.
     * @return amountRedeemed The amount of underlying asset received from redeeming all cTokens.
     */
    function redeemAllCTokens(address recipient) external override onlyVault returns (uint256 amountRedeemed) {
        if (recipient == address(0)) revert AddressZero();

        uint256 cTokenBalance = CTokenInterface(address(_cToken)).balanceOf(address(this));
        if (cTokenBalance == 0) {
            return 0;
        }

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult; // Silence compiler warning

        uint256 balanceBefore = _asset.balanceOf(address(this));

        uint256 redeemResult = _cToken.redeem(cTokenBalance);
        if (redeemResult != 0) {
            console.log("LendingManager.redeemAllCTokens: cToken.redeem failed with code:", redeemResult);
            revert RedeemFailed();
        }

        uint256 balanceAfter = _asset.balanceOf(address(this));
        amountRedeemed = balanceAfter - balanceBefore;

        // Update total principal tracking - Assume dust is yield for now.

        if (amountRedeemed > 0) {
            _asset.safeTransfer(recipient, amountRedeemed);
        }

        emit WithdrawFromProtocol(recipient, amountRedeemed);
        return amountRedeemed;
    }

    // --- View Functions ---
    // Note: The public state variable `totalPrincipalDeposited` automatically provides a getter function.
    // The explicit function below was removed to resolve the compiler error (Identifier already declared).
    // /**
    //  * @notice Returns the total principal amount deposited by the Vault into the lending protocol.
    //  * @return The total principal deposited in the underlying asset's units.
    //  */
    // function totalPrincipalDeposited() external view override returns (uint256) {
    //     return totalPrincipalDeposited;
    // }
}
