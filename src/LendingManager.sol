// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {RolesBase} from "./RolesBase.sol";
import {CrossContractSecurity} from "./CrossContractSecurity.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Roles} from "./Roles.sol";

import {ILendingManager} from "./interfaces/ILendingManager.sol";
import {CErc20Interface, CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

/**
 * @title LendingManager (Compound V2 Fork Adapter)
 * @notice Manages deposits and withdrawals to a specific Compound V2 fork cToken market.
 */
contract LendingManager is ILendingManager, RolesBase, CrossContractSecurity {
    using SafeERC20 for IERC20;

    bytes32 public constant OPERATOR_ROLE = Roles.OPERATOR_ROLE;
    bytes32 public constant ADMIN_ROLE = Roles.ADMIN_ROLE;

    // Custom errors
    error AccrueInterestFailed(uint256 errorCode);
    error CollateralFactorExceedsLimit(uint256 factor, uint256 maxFactor);
    error LiquidationIncentiveExceedsLimit(uint256 incentive, uint256 maxIncentive);

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

    constructor(address initialAdmin, address vaultAddress, address _assetAddress, address _cTokenAddress)
        RolesBase(initialAdmin)
    {
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

        _grantRole(OPERATOR_ROLE, vaultAddress);

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
        if (!hasRole(OPERATOR_ROLE, msg.sender)) {
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
        circuitBreakerProtected(keccak256("cToken.mint"))
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
                _recordCircuitFailure(keccak256("cToken.mint"));
                revert LendingManagerCTokenMintFailed(mintResult);
            }
        } catch Error(string memory reason) {
            _recordCircuitFailure(keccak256("cToken.mint"));
            revert LendingManagerCTokenMintFailedReason(reason);
        } catch (bytes memory data) {
            _recordCircuitFailure(keccak256("cToken.mint"));
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
        circuitBreakerProtected(keccak256("cToken.redeemUnderlying"))
        returns (bool success)
    {
        if (amount == 0) return true;

        uint256 accrualResult = CTokenInterface(address(_cToken)).accrueInterest();
        if (accrualResult != 0) revert AccrueInterestFailed(accrualResult);

        uint256 availableBalance = totalAssets();
        if (availableBalance < amount) {
            revert InsufficientBalanceInProtocol();
        }

        uint256 balanceBeforeRedeem = _asset.balanceOf(address(this));
        try _cToken.redeemUnderlying(amount) returns (uint256 redeemResult) {
            if (redeemResult != 0) {
                _recordCircuitFailure(keccak256("cToken.redeemUnderlying"));
                revert LendingManagerCTokenRedeemUnderlyingFailed(redeemResult);
            }
        } catch Error(string memory reason) {
            _recordCircuitFailure(keccak256("cToken.redeemUnderlying"));
            revert LendingManagerCTokenRedeemUnderlyingFailedReason(reason);
        } catch (bytes memory data) {
            _recordCircuitFailure(keccak256("cToken.redeemUnderlying"));
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

    function grantVaultRole(address newVault) external onlyRoleWhenNotPaused(ADMIN_ROLE) nonReentrant {
        if (newVault == address(0)) revert AddressZero();
        _grantRole(OPERATOR_ROLE, newVault);
        emit LendingManagerRoleGranted(OPERATOR_ROLE, newVault, msg.sender, block.timestamp);
    }

    function revokeVaultRole(address vault) external onlyRoleWhenNotPaused(ADMIN_ROLE) nonReentrant {
        if (vault == address(0)) revert AddressZero();
        _revokeRole(OPERATOR_ROLE, vault);
        emit LendingManagerRoleRevoked(OPERATOR_ROLE, vault, msg.sender, block.timestamp);
    }

    function grantAdminRole(address newAdmin) external onlyRoleWhenNotPaused(ADMIN_ROLE) nonReentrant {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
        emit LendingManagerRoleGranted(ADMIN_ROLE, newAdmin, msg.sender, block.timestamp);
    }

    function revokeAdminRole(address admin) external onlyRoleWhenNotPaused(ADMIN_ROLE) nonReentrant {
        if (admin == address(0)) revert AddressZero();
        require(getRoleMemberCount(ADMIN_ROLE) > 1, "Cannot remove last admin");
        _revokeRole(ADMIN_ROLE, admin);
        emit LendingManagerRoleRevoked(ADMIN_ROLE, admin, msg.sender, block.timestamp);
    }

    function grantAdminRoleAsDefaultAdmin(address newAdmin)
        external
        onlyRoleWhenNotPaused(DEFAULT_ADMIN_ROLE)
        nonReentrant
    {
        if (newAdmin == address(0)) revert AddressZero();
        _grantRole(ADMIN_ROLE, newAdmin);
        emit LendingManagerRoleGranted(ADMIN_ROLE, newAdmin, msg.sender, block.timestamp);
    }

    function revokeAdminRoleAsDefaultAdmin(address admin)
        external
        onlyRoleWhenNotPaused(DEFAULT_ADMIN_ROLE)
        nonReentrant
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
    function resetTotalPrincipalDeposited() external onlyRoleWhenNotPaused(ADMIN_ROLE) nonReentrant {
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
        circuitBreakerProtected(keccak256("cToken.repayBorrowBehalf"))
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
            _recordCircuitFailure(keccak256("cToken.repayBorrowBehalf"));
            revert LendingManagerCTokenRepayBorrowBehalfFailedReason(reason);
        } catch (bytes memory data) {
            _recordCircuitFailure(keccak256("cToken.repayBorrowBehalf"));
            revert LendingManagerCTokenRepayBorrowBehalfFailedBytes(data);
        }

        if (cTokenError != 0) {
            _recordCircuitFailure(keccak256("cToken.repayBorrowBehalf"));
            revert LendingManagerCTokenRepayBorrowBehalfFailed(cTokenError);
        }

        totalBorrowVolume += repayAmount;
        emit BorrowVolumeUpdated(totalBorrowVolume, repayAmount, block.timestamp);

        return cTokenError;
    }

    function updateExchangeRate() external onlyRoleWhenNotPaused(ADMIN_ROLE) returns (uint256 newRate) {
        newRate = CTokenInterface(address(_cToken)).exchangeRateCurrent();
        cachedExchangeRate = newRate;
        lastExchangeRateTimestamp = block.timestamp;
    }

    // --- Statistical Tracking Functions ---

    function updateMarketParticipants(uint256 _totalMarketParticipants) external onlyRoleWhenNotPaused(ADMIN_ROLE) {
        totalMarketParticipants = _totalMarketParticipants;
    }

    function recordLiquidationVolume(uint256 liquidationAmount) external onlyRoleWhenNotPaused(ADMIN_ROLE) {
        totalLiquidationVolume += liquidationAmount;
        emit LiquidationVolumeUpdated(totalLiquidationVolume, liquidationAmount, block.timestamp);
    }

    function setGlobalCollateralFactor(uint256 _globalCollateralFactor) external onlyRoleWhenNotPaused(ADMIN_ROLE) {
        if (_globalCollateralFactor > BASIS_POINTS_DENOMINATOR) {
            revert CollateralFactorExceedsLimit(_globalCollateralFactor, BASIS_POINTS_DENOMINATOR);
        }
        globalCollateralFactor = _globalCollateralFactor;
        emit GlobalCollateralFactorUpdated(_globalCollateralFactor, block.timestamp);
    }

    function setLiquidationIncentive(uint256 _liquidationIncentive) external onlyRoleWhenNotPaused(ADMIN_ROLE) {
        if (_liquidationIncentive > BASIS_POINTS_DENOMINATOR) {
            revert LiquidationIncentiveExceedsLimit(_liquidationIncentive, BASIS_POINTS_DENOMINATOR);
        }
        liquidationIncentive = _liquidationIncentive;
        emit LiquidationIncentiveUpdated(_liquidationIncentive, block.timestamp);
    }

    function addSupportedMarket(address market) external onlyRoleWhenNotPaused(ADMIN_ROLE) {
        if (market == address(0)) revert AddressZero();
        if (!supportedMarkets[market]) {
            supportedMarkets[market] = true;
            emit SupportedMarketAdded(market, block.timestamp);
        }
    }

    function removeSupportedMarket(address market) external onlyRoleWhenNotPaused(ADMIN_ROLE) {
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
}
