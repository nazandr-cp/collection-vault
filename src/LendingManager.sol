// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Roles} from "./Roles.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

/**
 * @title LendingManager (Compound V2 Fork Adapter)
 * @notice Manages deposits and withdrawals to a specific Compound V2 fork cToken market.
 */
contract LendingManager is ILendingManager, AccessControlEnumerable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = Roles.VAULT_ROLE;
    bytes32 public constant ADMIN_ROLE = Roles.ADMIN_ROLE;

    uint256 public constant R0_BASIS_POINTS = 5;
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant EXCHANGE_RATE_DENOMINATOR = 1e18;
    uint256 private constant REDEEM_TOLERANCE = 1;
    IERC20 private immutable _asset;
    uint8 private immutable underlyingDecimals;
    uint8 private immutable cTokenDecimals;
    CErc20Interface internal immutable _cToken;

    uint256 public totalPrincipalDeposited;
    uint256 public cachedExchangeRate;
    uint256 public lastExchangeRateTimestamp;

    // Statistical tracking variables
    mapping(address => bool) public supportedMarkets;
    uint256 public totalMarketParticipants;
    uint256 public totalSupplyVolume;
    uint256 public totalBorrowVolume;
    uint256 public totalLiquidationVolume;

    // Risk parameters
    uint256 public globalCollateralFactor;
    uint256 public liquidationIncentive;

    constructor(address initialAdmin, address vaultAddress, address _assetAddress, address _cTokenAddress) {
        if (
            initialAdmin == address(0) || vaultAddress == address(0) || _assetAddress == address(0)
                || _cTokenAddress == address(0)
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

        _asset.approve(address(_cToken), type(uint256).max);

        cachedExchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        lastExchangeRateTimestamp = block.timestamp;

        supportedMarkets[address(_cToken)] = true;
        totalMarketParticipants = 0;
        totalSupplyVolume = 0;
        totalBorrowVolume = 0;
        totalLiquidationVolume = 0;

        globalCollateralFactor = 7500;
        liquidationIncentive = 500;
    }

    modifier onlyVault() {
        if (!hasRole(VAULT_ROLE, msg.sender)) {
            revert LM_CallerNotVault(msg.sender);
        }
        _;
    }

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
        totalSupplyVolume += amount;

        emit DepositToProtocol(msg.sender, amount);
        emit SupplyVolumeUpdated(totalSupplyVolume, amount, block.timestamp);
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
        uint256 rate = cachedExchangeRate;
        if (cTokenBalance == 0 || rate == 0) {
            return 0;
        }
        return (cTokenBalance * rate) / EXCHANGE_RATE_DENOMINATOR;
    }

    // --- Administrative Functions for Role Management ---

    function grantVaultRole(address newVault) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (newVault == address(0)) revert AddressZero();
        _grantRole(VAULT_ROLE, newVault);
        emit LendingManagerRoleGranted(VAULT_ROLE, newVault, msg.sender, block.timestamp);
    }

    function revokeVaultRole(address vault) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (vault == address(0)) revert AddressZero();
        _revokeRole(VAULT_ROLE, vault);
        emit LendingManagerRoleRevoked(VAULT_ROLE, vault, msg.sender, block.timestamp);
    }

    function grantAdminRole(address newAdmin) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
        emit LendingManagerRoleGranted(ADMIN_ROLE, newAdmin, msg.sender, block.timestamp);
    }

    function revokeAdminRole(address admin) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (admin == address(0)) revert AddressZero();
        require(getRoleMemberCount(ADMIN_ROLE) > 1, "Cannot remove last admin");
        _revokeRole(ADMIN_ROLE, admin);
        emit LendingManagerRoleRevoked(ADMIN_ROLE, admin, msg.sender, block.timestamp);
    }

    function grantAdminRoleAsDefaultAdmin(address newAdmin)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        nonReentrant
        whenNotPaused
    {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
        emit LendingManagerRoleGranted(ADMIN_ROLE, newAdmin, msg.sender, block.timestamp);
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
        emit LendingManagerRoleRevoked(ADMIN_ROLE, admin, msg.sender, block.timestamp);
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
        accrualResult;

        uint256 exchangeRate = CTokenInterface(address(_cToken)).exchangeRateStored();
        if (exchangeRate == 0 && cTokenBalance > 0) {
            revert LendingManager__BalanceCheckFailed("LM: redeemAll cToken.redeem exchange rate is zero", 1, 0);
        }
        uint256 expectedUnderlyingToReceive = (cTokenBalance * exchangeRate) / EXCHANGE_RATE_DENOMINATOR;

        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this));
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
        amountRedeemed = balanceAfterRedeem - balanceBeforeRedeem;

        uint256 diff = amountRedeemed > expectedUnderlyingToReceive
            ? amountRedeemed - expectedUnderlyingToReceive
            : expectedUnderlyingToReceive - amountRedeemed;
        if (diff > REDEEM_TOLERANCE) {
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

    function repayBorrowBehalf(address borrower, uint256 repayAmount)
        external
        override
        onlyVault
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        if (borrower == address(0)) revert AddressZero();
        if (repayAmount == 0) return 0;

        uint256 balanceBeforeTransfer = _asset.balanceOf(address(this));
        _asset.safeTransferFrom(msg.sender, address(this), repayAmount);
        uint256 balanceAfterTransfer = _asset.balanceOf(address(this));
        if (balanceAfterTransfer != balanceBeforeTransfer + repayAmount) {
            revert LendingManager__BalanceCheckFailed(
                "LM: repayBehalf asset receipt mismatch", balanceBeforeTransfer + repayAmount, balanceAfterTransfer
            );
        }

        uint256 cTokenError;
        try _cToken.repayBorrowBehalf(borrower, repayAmount) returns (uint256 repayResult) {
            cTokenError = repayResult;
        } catch Error(string memory reason) {
            revert LendingManagerCTokenRepayBorrowBehalfFailedReason(reason);
        } catch (bytes memory data) {
            revert LendingManagerCTokenRepayBorrowBehalfFailedBytes(data);
        }

        if (cTokenError != 0) {
            revert LendingManagerCTokenRepayBorrowBehalfFailed(cTokenError);
        }

        totalBorrowVolume += repayAmount;
        emit BorrowVolumeUpdated(totalBorrowVolume, repayAmount, block.timestamp);

        return cTokenError;
    }

    function updateExchangeRate() external onlyRole(ADMIN_ROLE) whenNotPaused returns (uint256 newRate) {
        newRate = CTokenInterface(address(_cToken)).exchangeRateCurrent();
        cachedExchangeRate = newRate;
        lastExchangeRateTimestamp = block.timestamp;
    }

    // --- Statistical Tracking Functions ---

    function updateMarketParticipants(uint256 _totalMarketParticipants) external onlyRole(ADMIN_ROLE) whenNotPaused {
        totalMarketParticipants = _totalMarketParticipants;
    }

    function recordLiquidationVolume(uint256 liquidationAmount) external onlyRole(ADMIN_ROLE) whenNotPaused {
        totalLiquidationVolume += liquidationAmount;
        emit LiquidationVolumeUpdated(totalLiquidationVolume, liquidationAmount, block.timestamp);
    }

    function setGlobalCollateralFactor(uint256 _globalCollateralFactor) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_globalCollateralFactor <= BASIS_POINTS_DENOMINATOR, "Collateral factor cannot exceed 100%");
        globalCollateralFactor = _globalCollateralFactor;
        emit GlobalCollateralFactorUpdated(_globalCollateralFactor, block.timestamp);
    }

    function setLiquidationIncentive(uint256 _liquidationIncentive) external onlyRole(ADMIN_ROLE) whenNotPaused {
        require(_liquidationIncentive <= BASIS_POINTS_DENOMINATOR, "Liquidation incentive cannot exceed 100%");
        liquidationIncentive = _liquidationIncentive;
        emit LiquidationIncentiveUpdated(_liquidationIncentive, block.timestamp);
    }

    function addSupportedMarket(address market) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (market == address(0)) revert AddressZero();
        if (!supportedMarkets[market]) {
            supportedMarkets[market] = true;
            emit SupportedMarketAdded(market, block.timestamp);
        }
    }

    function removeSupportedMarket(address market) external onlyRole(ADMIN_ROLE) whenNotPaused {
        if (market == address(0)) revert AddressZero();
        if (supportedMarkets[market]) {
            supportedMarkets[market] = false;
            emit SupportedMarketRemoved(market, block.timestamp);
        }
    }

    // --- Getter Functions for Statistics ---

    function getSupportedMarkets() external view returns (address[] memory markets) {
        markets = new address[](1);
        markets[0] = address(_cToken);
    }

    function getTotalMarketParticipants() external view returns (uint256) {
        return totalMarketParticipants;
    }

    function getTotalSupplyVolume() external view returns (uint256) {
        return totalSupplyVolume;
    }

    function getTotalBorrowVolume() external view returns (uint256) {
        return totalBorrowVolume;
    }

    function getTotalLiquidationVolume() external view returns (uint256) {
        return totalLiquidationVolume;
    }

    function getGlobalCollateralFactor() external view returns (uint256) {
        return globalCollateralFactor;
    }

    function getLiquidationIncentive() external view returns (uint256) {
        return liquidationIncentive;
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
