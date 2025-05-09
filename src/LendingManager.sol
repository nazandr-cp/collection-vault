// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

/**
 * @title LendingManager (Compound V2 Fork Adapter)
 * @notice Manages deposits and withdrawals to a specific Compound V2 fork cToken market.
 */
contract LendingManager is ILendingManager, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");

    bytes32 public constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

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

    CErc20Interface internal immutable _cToken;

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

    event YieldTransferred(address indexed recipient, uint256 amount);
    event YieldTransferredBatch(
        address indexed recipient, uint256 totalAmount, address[] collections, uint256[] amounts
    );
    event DepositToProtocol(address indexed caller, uint256 amount);
    event WithdrawFromProtocol(address indexed caller, uint256 amount);

    error MintFailed();
    error RedeemFailed();
    error TransferYieldFailed();
    error AddressZero();
    error InsufficientBalanceInProtocol();
    error LM_CallerNotVault(address caller);
    error LM_CallerNotRewardsController(address caller);
    error CannotRemoveLastAdmin(bytes32 role);

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

    function depositToLendingProtocol(uint256 amount) external override onlyVault returns (bool success) {
        if (amount == 0) {
            return true;
        }

        _asset.safeTransferFrom(msg.sender, address(this), amount);

        uint256 mintResult = _cToken.mint(amount);
        if (mintResult != 0) {
            revert MintFailed();
        }

        totalPrincipalDeposited += amount;

        emit DepositToProtocol(msg.sender, amount);
        return true;
    }

    function withdrawFromLendingProtocol(uint256 amount) external override onlyVault returns (bool success) {
        if (amount == 0) return true;

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        require(accrualResult == 0, "Accrue interest failed");

        uint256 availableBalance = totalAssets();
        if (availableBalance < amount) {
            revert InsufficientBalanceInProtocol();
        }

        uint256 redeemResult = _cToken.redeemUnderlying(amount);
        if (redeemResult != 0) {
            revert RedeemFailed();
        }

        _asset.safeTransfer(msg.sender, amount);

        if (totalPrincipalDeposited >= amount) {
            totalPrincipalDeposited -= amount;
        } else {
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

    function getBaseRewardPerBlock() external view override returns (uint256) {
        uint256 currentTotalAssets = totalAssets();
        if (currentTotalAssets == 0) {
            return 0;
        }
        return (currentTotalAssets * R0_BASIS_POINTS) / BASIS_POINTS_DENOMINATOR;
    }

    function transferYield(uint256 amount, address recipient)
        external
        override
        onlyRewardsController
        returns (uint256 amountTransferred)
    {
        if (amount == 0) return 0;
        if (recipient == address(0)) revert AddressZero();

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult;

        uint256 availableBalance = totalAssets();
        uint256 availableYield =
            availableBalance > totalPrincipalDeposited ? availableBalance - totalPrincipalDeposited : 0;

        if (amount > availableYield) {
            amountTransferred = availableYield;
        } else {
            amountTransferred = amount;
        }

        if (amountTransferred == 0) return 0;

        uint256 exchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        if (exchangeRate == 0) return 0;
        uint256 cTokensToRedeem = (amountTransferred * EXCHANGE_RATE_DENOMINATOR) / exchangeRate;

        if (cTokensToRedeem == 0 && amountTransferred > 0) {
            return 0;
        }
        if (cTokensToRedeem == 0 && amountTransferred > 0) {
            return 0;
        }
        if (cTokensToRedeem == 0) {
            return 0;
        }

        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this));

        uint256 redeemResult = _cToken.redeem(cTokensToRedeem);
        if (redeemResult != 0) {
            revert RedeemFailed();
        }

        uint256 balanceAfterRedeem = _asset.balanceOf(address(this));

        uint256 actualAmountReceived = balanceAfterRedeem - balanceBeforeRedeem;

        if (actualAmountReceived > 0) {
            _asset.safeTransfer(recipient, actualAmountReceived);
        }

        emit YieldTransferred(recipient, actualAmountReceived);
        return actualAmountReceived;
    }

    function transferYieldBatch(
        address[] calldata collections,
        uint256[] calldata amounts,
        uint256 totalAmount,
        address recipient
    ) external override onlyRewardsController returns (uint256 totalAmountTransferredOutput) {
        if (totalAmount == 0) return 0;
        if (recipient == address(0)) revert AddressZero();
        if (collections.length != amounts.length) revert("Array length mismatch");

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult;

        uint256 availableBalance = totalAssets();
        uint256 availableYield =
            availableBalance > totalPrincipalDeposited ? availableBalance - totalPrincipalDeposited : 0;

        uint256 cappedTotalAmountToAttempt;
        if (totalAmount > availableYield) {
            cappedTotalAmountToAttempt = availableYield;
        } else {
            cappedTotalAmountToAttempt = totalAmount;
        }

        if (cappedTotalAmountToAttempt == 0) return 0;

        uint256 exchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        if (exchangeRate == 0) return 0;
        uint256 cTokensToRedeem = (cappedTotalAmountToAttempt * EXCHANGE_RATE_DENOMINATOR) / exchangeRate;

        if (cTokensToRedeem == 0 && cappedTotalAmountToAttempt > 0) {
            return 0;
        }
        if (cTokensToRedeem == 0 && cappedTotalAmountToAttempt > 0) {
            return 0;
        }
        if (cTokensToRedeem == 0) {
            return 0;
        }

        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this));

        uint256 redeemResult = _cToken.redeem(cTokensToRedeem);
        if (redeemResult != 0) {
            revert RedeemFailed();
        }

        uint256 balanceAfterRedeem = _asset.balanceOf(address(this));

        uint256 actualAmountReceived = balanceAfterRedeem - balanceBeforeRedeem;

        if (actualAmountReceived > 0) {
            _asset.safeTransfer(recipient, actualAmountReceived);
        }

        emit YieldTransferredBatch(recipient, actualAmountReceived, collections, amounts);
        return actualAmountReceived;
    }

    function grantRewardsControllerRole(address newController) external onlyRole(ADMIN_ROLE) {
        if (newController == address(0)) revert AddressZero();
        _grantRole(REWARDS_CONTROLLER_ROLE, newController);
    }

    function revokeRewardsControllerRole(address controller) external onlyRole(ADMIN_ROLE) {
        if (controller == address(0)) revert AddressZero();
        _revokeRole(REWARDS_CONTROLLER_ROLE, controller);
    }

    // --- Administrative Functions for Role Management ---

    function grantVaultRole(address newVault) external onlyRole(ADMIN_ROLE) {
        if (newVault == address(0)) revert AddressZero();
        _grantRole(VAULT_ROLE, newVault);
    }

    function revokeVaultRole(address vault) external onlyRole(ADMIN_ROLE) {
        if (vault == address(0)) revert AddressZero();
        _revokeRole(VAULT_ROLE, vault);
    }

    function grantAdminRole(address newAdmin) external onlyRole(ADMIN_ROLE) {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    function revokeAdminRole(address admin) external onlyRole(ADMIN_ROLE) {
        if (admin == address(0)) revert AddressZero();
        _revokeRole(ADMIN_ROLE, admin);
    }

    function grantAdminRoleAsDefaultAdmin(address newAdmin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
    }

    function revokeAdminRoleAsDefaultAdmin(address admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (admin == address(0)) revert AddressZero();
        _revokeRole(ADMIN_ROLE, admin);
    }

    function redeemAllCTokens(address recipient) external override onlyVault returns (uint256 amountRedeemed) {
        if (recipient == address(0)) revert AddressZero();

        uint256 cTokenBalance = CTokenInterface(address(_cToken)).balanceOf(address(this));
        if (cTokenBalance == 0) {
            return 0;
        }

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        accrualResult;

        uint256 balanceBefore = _asset.balanceOf(address(this));

        uint256 redeemResult = _cToken.redeem(cTokenBalance);
        if (redeemResult != 0) {
            revert RedeemFailed();
        }

        uint256 balanceAfter = _asset.balanceOf(address(this));
        amountRedeemed = balanceAfter - balanceBefore;

        if (amountRedeemed > 0) {
            _asset.safeTransfer(recipient, amountRedeemed);
        }

        emit WithdrawFromProtocol(recipient, amountRedeemed);
        return amountRedeemed;
    }
}
