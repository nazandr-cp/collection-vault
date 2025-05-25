// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

/**
 * @title LendingManager (Compound V2 Fork Adapter)
 * @notice Manages deposits and withdrawals to a specific Compound V2 fork cToken market.
 */
contract LendingManager is ILendingManager, AccessControlEnumerable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    bytes32 public constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 private immutable _asset;
    uint8 private immutable underlyingDecimals;
    uint8 private immutable cTokenDecimals;
    CErc20Interface internal immutable _cToken;

    /**
     * @notice Get the underlying ERC20 asset managed by the lending manager.
     * @return ERC20 asset address.
     */
    function asset() external view override returns (IERC20) {
        return _asset;
    }

    /**
     * @notice Get the cToken address associated with the underlying asset.
     * @return cToken address.
     */
    function cToken() external view override returns (address) {
        return address(_cToken);
    }

    uint256 public constant R0_BASIS_POINTS = 5;

    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant PRECISION = 1e18;

    uint256 private constant EXCHANGE_RATE_DENOMINATOR = 1e18;

    uint256 public totalPrincipalDeposited;
    uint256 public constant MAX_BATCH_SIZE = 50;

    constructor(
        address initialAdmin,
        address vaultAddress,
        address rewardsControllerAddress,
        address _assetAddress,
        address _cTokenAddress
    ) {
        if (
            initialAdmin == address(0) || vaultAddress == address(0) || rewardsControllerAddress == address(0)
                || _assetAddress == address(0) || _cTokenAddress == address(0)
        ) {
            revert AddressZero();
        }

        // Set immutable state variables.
        _asset = IERC20(_assetAddress);
        _cToken = CErc20Interface(_cTokenAddress);

        underlyingDecimals = IERC20Metadata(_assetAddress).decimals();
        cTokenDecimals = IERC20Metadata(_cTokenAddress).decimals();

        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(VAULT_ROLE, vaultAddress);
        _grantRole(REWARDS_CONTROLLER_ROLE, rewardsControllerAddress);

        _asset.approve(address(_cToken), type(uint256).max);
    }

    modifier onlyVault() {
        if (!hasRole(VAULT_ROLE, msg.sender)) {
            revert LM_CallerNotVault(msg.sender);
        }
        _;
    }

    modifier onlyRewardsController() {
        if (!hasRole(REWARDS_CONTROLLER_ROLE, msg.sender)) {
            revert LM_CallerNotRewardsController(msg.sender);
        }
        _;
    }

    function depositToLendingProtocol(uint256 amount)
        external
        override
        onlyVault
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        if (amount == 0) {
            return true;
        }

        uint256 balanceBeforeTransfer = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfterTransfer = _asset.balanceOf(address(this));
        if (balanceAfterTransfer != balanceBeforeTransfer + amount) {
            revert LendingManager__BalanceCheckFailed(
                "LM: deposit asset receipt mismatch", balanceBeforeTransfer + amount, balanceAfterTransfer
            );
        }

        uint256 balanceBeforeMint = _asset.balanceOf(address(this));
        try _cToken.mint(amount) returns (uint256 mintResult) {
            if (mintResult != 0) {
                revert LendingManagerCTokenMintFailed(mintResult);
            }
        } catch Error(string memory reason) {
            revert LendingManagerCTokenMintFailedReason(reason);
        } catch (bytes memory data) {
            revert LendingManagerCTokenMintFailedBytes(data);
        }

        uint256 balanceAfterMint = _asset.balanceOf(address(this));
        if (balanceAfterMint != balanceBeforeMint - amount) {
            revert LendingManager__BalanceCheckFailed(
                "LM: deposit cToken.mint supply mismatch", balanceBeforeMint - amount, balanceAfterMint
            );
        }

        totalPrincipalDeposited += amount;

        emit DepositToProtocol(msg.sender, amount);
        return true;
    }

    function withdrawFromLendingProtocol(uint256 amount)
        external
        override
        onlyVault
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        if (amount == 0) return true;

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        require(accrualResult == 0, "Accrue interest failed");

        uint256 availableBalance = totalAssets();
        if (availableBalance < amount) {
            revert InsufficientBalanceInProtocol();
        }

        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this));
        try _cToken.redeemUnderlying(amount) returns (uint256 redeemResult) {
            if (redeemResult != 0) {
                revert LendingManagerCTokenRedeemUnderlyingFailed(redeemResult);
            }
        } catch Error(string memory reason) {
            revert LendingManagerCTokenRedeemUnderlyingFailedReason(reason);
        } catch (bytes memory data) {
            revert LendingManagerCTokenRedeemUnderlyingFailedBytes(data);
        }
        uint256 balanceAfterRedeem = _asset.balanceOf(address(this));
        // If redeemUnderlying(amount) is successful, this contract should receive 'amount' of the underlying asset.
        if (balanceAfterRedeem != balanceBeforeRedeem + amount) {
            revert LendingManager__BalanceCheckFailed(
                "LM: withdraw cToken.redeemUnderlying receipt mismatch",
                balanceBeforeRedeem + amount,
                balanceAfterRedeem
            );
        }

        uint256 balanceBeforeTransfer = _asset.balanceOf(address(this));
        _asset.safeTransfer(msg.sender, amount);
        uint256 balanceAfterTransfer = _asset.balanceOf(address(this));
        if (balanceAfterTransfer != balanceBeforeTransfer - amount) {
            revert LendingManager__BalanceCheckFailed(
                "LM: withdraw asset send mismatch", balanceBeforeTransfer - amount, balanceAfterTransfer
            );
        }
        if (totalPrincipalDeposited >= amount) {
            totalPrincipalDeposited -= amount;
        } else {
            emit PrincipalReset(totalPrincipalDeposited, msg.sender);
            totalPrincipalDeposited = 0;
        }

        emit WithdrawFromProtocol(msg.sender, amount);
        return true;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 cTokenBalance = CTokenInterface(address(_cToken)).balanceOf(address(this));
        uint256 currentExchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        uint256 underlyingBalanceInCToken;
        if (cTokenBalance > 0 && currentExchangeRate > 0) {
            underlyingBalanceInCToken = (cTokenBalance * currentExchangeRate) / EXCHANGE_RATE_DENOMINATOR;
        }
        return underlyingBalanceInCToken;
    }

    // TODO: remove
    function getBaseRewardPerBlock() external view override returns (uint256) {
        uint256 currentTotalAssets = totalAssets();
        if (currentTotalAssets == 0) {
            return 0;
        }
        return (currentTotalAssets * R0_BASIS_POINTS) / BASIS_POINTS_DENOMINATOR;
    }

    function grantRewardsControllerRole(address newController)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (newController == address(0)) revert AddressZero();
        _grantRole(REWARDS_CONTROLLER_ROLE, newController);
    }

    function revokeRewardsControllerRole(address controller) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (controller == address(0)) revert AddressZero();
        _revokeRole(REWARDS_CONTROLLER_ROLE, controller);
    }

    // --- Administrative Functions for Role Management ---

    function grantVaultRole(address newVault) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (newVault == address(0)) revert AddressZero();
        _grantRole(VAULT_ROLE, newVault);
    }

    function revokeVaultRole(address vault) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (vault == address(0)) revert AddressZero();
        _revokeRole(VAULT_ROLE, vault);
    }

    function grantAdminRole(address newAdmin) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    function revokeAdminRole(address admin) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (admin == address(0)) revert AddressZero();
        require(getRoleMemberCount(ADMIN_ROLE) > 1, "Cannot remove last admin");
        _revokeRole(ADMIN_ROLE, admin);
    }

    function grantAdminRoleAsDefaultAdmin(address newAdmin)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    function revokeAdminRoleAsDefaultAdmin(address admin)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (admin == address(0)) revert AddressZero();
        require(getRoleMemberCount(ADMIN_ROLE) > 1, "Cannot remove last admin");
        _revokeRole(ADMIN_ROLE, admin);
    }

    function redeemAllCTokens(address recipient)
        external
        override
        onlyVault
        nonReentrant
        whenNotPaused
        returns (uint256 amountRedeemed)
    {
        if (recipient == address(0)) revert AddressZero();

        uint256 cTokenBalance = CTokenInterface(address(_cToken)).balanceOf(address(this));
        if (cTokenBalance == 0) {
            return 0;
        }

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult; // Consume accrualResult to avoid unused variable warning

        // Calculate the expected amount of underlying tokens to receive *before* redemption.
        uint256 exchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        // This check is important because if exchangeRate is 0, the multiplication below would be 0.
        // While cTokenBalance > 0, if exchangeRate is 0, it implies an issue or no value.
        if (exchangeRate == 0 && cTokenBalance > 0) {
            // This case should ideally not happen if cTokens are held, but as a safeguard.
            revert LendingManager__BalanceCheckFailed("LM: redeemAll cToken.redeem exchange rate is zero", 1, 0);
        }
        uint256 expectedUnderlyingToReceive = (cTokenBalance * exchangeRate) / EXCHANGE_RATE_DENOMINATOR;

        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this));
        // uint256 redeemResult = _cToken.redeem(cTokenBalance); // Redeem all cTokens
        // if (redeemResult != 0) {
        //     revert RedeemFailed(); // Old generic error
        // }
        try _cToken.redeem(cTokenBalance) returns (uint256 redeemResult) {
            if (redeemResult != 0) {
                revert LendingManagerCTokenRedeemFailed(redeemResult);
            }
        } catch Error(string memory reason) {
            revert LendingManagerCTokenRedeemFailedReason(reason);
        } catch (bytes memory data) {
            revert LendingManagerCTokenRedeemFailedBytes(data);
        }
        uint256 balanceAfterRedeem = _asset.balanceOf(address(this));
        amountRedeemed = balanceAfterRedeem - balanceBeforeRedeem; // This is the actual amount received after any fees

        // Check if the actual amount received matches the expected amount (pre-fee).
        if (amountRedeemed != expectedUnderlyingToReceive) {
            revert LendingManager__BalanceCheckFailed(
                "LM: redeemAll cToken.redeem receipt mismatch", expectedUnderlyingToReceive, amountRedeemed
            );
        }

        if (amountRedeemed > 0) {
            uint256 balanceBeforeSend = _asset.balanceOf(address(this));
            _asset.safeTransfer(recipient, amountRedeemed);
            uint256 balanceAfterSend = _asset.balanceOf(address(this));
            if (balanceAfterSend != balanceBeforeSend - amountRedeemed) {
                revert LendingManager__BalanceCheckFailed(
                    "LM: redeemAll asset send mismatch", balanceBeforeSend - amountRedeemed, balanceAfterSend
                );
            }
        }

        emit WithdrawFromProtocol(recipient, amountRedeemed);
        return amountRedeemed;
    }

    /**
     * @notice Resets the total principal deposited to zero.
     * @dev This function is restricted to ADMIN_ROLE.
     * It emits a PrincipalReset event.
     */
    function resetTotalPrincipalDeposited() external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        uint256 oldValue = totalPrincipalDeposited;
        totalPrincipalDeposited = 0;
        emit PrincipalReset(oldValue, msg.sender);
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
