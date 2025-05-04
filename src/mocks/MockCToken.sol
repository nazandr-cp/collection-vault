// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CTokenInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {CErc20Interface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol"; // Added import
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ComptrollerInterface} from "compound-protocol-2.8.1/contracts/ComptrollerInterface.sol"; // Added import
import {InterestRateModel} from "compound-protocol-2.8.1/contracts/InterestRateModel.sol"; // Added import
import {EIP20NonStandardInterface} from "compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol"; // Added import

/**
 * @title MockCToken
 * @notice Mock for Compound cToken interactions in LendingManager tests.
 */
contract MockCToken is
    CTokenInterface,
    CErc20Interface // <-- Added inheritance
{
    // Moved inside the contract body
    bool public accrueInterestEnabled = true; // Flag to control accrual

    function setAccrueInterestEnabled(bool _enabled) external {
        accrueInterestEnabled = _enabled;
    }

    uint8 public constant UNDERLYING_DECIMALS = 18; // Assuming underlying is DAI
    // Use 1e18 scale to match observed mainnet behavior, not theoretical formula
    uint256 private constant EXCHANGE_RATE_SCALE = 1e18;

    // Stored rate should be scaled: 0.02 * 1e18 = 2e16
    uint256 public currentExchangeRate = 2e16; // 0.02 scaled by 1e18
    mapping(address => uint256) public cTokenBalances;

    uint256 public mintResult = 0;
    uint256 public redeemResult = 0;

    uint256 public exchangeRateMantissa; // Example: 2 * 10^(18 + underlyingDecimals - 8)
    uint256 public constant accrualIncrement = 1e24; // Increased increment

    constructor(address _underlying) {
        underlying = _underlying; // Initialize inherited state variable
        name = "Mock cToken"; // Initialize inherited state variable
        symbol = "mcTOK"; // Initialize inherited state variable
        decimals = 8; // Initialize inherited state variable
        initialExchangeRateMantissa = 2e28; // Set the default value for the inherited variable
        exchangeRateMantissa = initialExchangeRateMantissa; // Initialize current rate
    }

    // --- Mock Control Functions ---
    function setExchangeRate(uint256 _rate) external {
        // Assume input rate is scaled correctly
        currentExchangeRate = _rate;
    }

    function setMintResult(uint256 _result) external {
        mintResult = _result;
    }

    function setRedeemResult(uint256 _result) external {
        redeemResult = _result;
    }

    // --- MinimalCTokenInterface Implementation ---
    function mint(uint256 mintAmount) external override(CErc20Interface) returns (uint256) {
        // Added override specifier
        if (mintResult != 0) return mintResult;

        // Simulate transfer from caller (LendingManager) to this mock cToken
        IERC20(underlying).transferFrom(msg.sender, address(this), mintAmount);

        // Calculate cTokens using scaled rate: cTokens = underlying * scale / rate
        uint256 cTokensToMint = mintAmount * EXCHANGE_RATE_SCALE / currentExchangeRate;
        cTokenBalances[msg.sender] += cTokensToMint;

        emit Mint(msg.sender, mintAmount, cTokensToMint); // Use inherited event
        return 0; // Return 0 for success as per Compound interface
    }

    function redeemUnderlying(uint256 redeemUnderlyingAmount) external override(CErc20Interface) returns (uint256) {
        // Added override specifier
        if (redeemResult != 0) return redeemResult;

        // Calculate required cTokens using scaled rate: cTokens = underlying * scale / rate
        uint256 cTokensToBurn = redeemUnderlyingAmount * EXCHANGE_RATE_SCALE / currentExchangeRate;

        // Check if owner has enough cTokens
        require(cTokenBalances[msg.sender] >= cTokensToBurn, "MockCToken: Insufficient cTokens");

        // Check if this mock contract has enough underlying (simple check)
        require(
            IERC20(underlying).balanceOf(address(this)) >= redeemUnderlyingAmount,
            "MockCToken: Contract lacks underlying"
        );

        cTokenBalances[msg.sender] -= cTokensToBurn;
        // Simulate transferring underlying back to the caller (LendingManager)
        IERC20(underlying).transfer(msg.sender, redeemUnderlyingAmount);

        emit Redeem(msg.sender, redeemUnderlyingAmount, cTokensToBurn); // Use inherited event
        return 0; // Return 0 for success as per Compound interface
    }

    // --- ADDED: Mock Implementation for redeem --- //
    function redeem(uint256 redeemTokens) external override(CErc20Interface) returns (uint256) {
        // Added override specifier
        // Calculate underlying amount based on tokens and rate
        uint256 underlyingToRedeem = redeemTokens * currentExchangeRate / EXCHANGE_RATE_SCALE;

        require(cTokenBalances[msg.sender] >= redeemTokens, "MockCToken: Insufficient cTokens");
        require(
            IERC20(underlying).balanceOf(address(this)) >= underlyingToRedeem, "MockCToken: Contract lacks underlying"
        );

        cTokenBalances[msg.sender] -= redeemTokens;
        IERC20(underlying).transfer(msg.sender, underlyingToRedeem);

        emit Redeem(msg.sender, underlyingToRedeem, redeemTokens);
        return 0;
    }

    // --- ADDED: Mock Implementation for accrueInterest --- //
    function accrueInterest() external override returns (uint256) {
        // Simulate interest accrual by slightly increasing the exchange rate
        if (accrueInterestEnabled) {
            exchangeRateMantissa += accrualIncrement; // Use increased increment
        }
        emit AccrueInterest(0, 0, exchangeRateMantissa, 0); // Emit event with new rate
        return 0; // Return value often ignored, 0 is fine for mock
    }

    // Correctly calculate underlying based on cTokens and scaled rate
    function balanceOfUnderlying(address owner) public view override returns (uint256) {
        uint256 cTokenBalance = cTokenBalances[owner];
        if (cTokenBalance == 0) {
            return 0;
        }
        // underlying = cTokens * rate / scale
        return cTokenBalance * currentExchangeRate / EXCHANGE_RATE_SCALE;
    }

    function exchangeRateStored() external view override returns (uint256) {
        return exchangeRateMantissa;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return cTokenBalances[owner];
    }

    // --- Added Minimal Implementations for Abstract Functions ---

    // These are needed to avoid the 'abstract contract' error.
    // They don't need complex logic for the current tests.

    function _acceptAdmin() external virtual override returns (uint256) {
        return 0;
    }

    function _reduceReserves(uint256 /* reduceAmount */ ) external virtual override returns (uint256) {
        return 0;
    }

    function _setComptroller(ComptrollerInterface /* newComptroller */ ) external virtual override returns (uint256) {
        return 0;
    }

    function _setInterestRateModel(InterestRateModel /* newInterestRateModel */ )
        external
        virtual
        override
        returns (uint256)
    {
        return 0;
    }

    function _setPendingAdmin(address payable /* newPendingAdmin */ ) external virtual override returns (uint256) {
        return 0;
    }

    function _setReserveFactor(uint256 /* newReserveFactorMantissa */ ) external virtual override returns (uint256) {
        return 0;
    }

    function allowance(address, /* owner */ address /* spender */ ) external view virtual override returns (uint256) {
        return type(uint256).max;
    } // Assume max allowance for simplicity

    function approve(address, /* spender */ uint256 /* amount */ ) external virtual override returns (bool) {
        return true;
    }

    function borrowBalanceCurrent(address /* account */ ) external virtual override returns (uint256) {
        return 0;
    }

    function borrowBalanceStored(address /* account */ ) external view virtual override returns (uint256) {
        return 0;
    }

    function borrowRatePerBlock() external view virtual override returns (uint256) {
        return 0;
    }

    function exchangeRateCurrent() external virtual override returns (uint256) {
        this.accrueInterest();
        return this.exchangeRateStored();
    } // Match CErc20Delegator behavior

    function getAccountSnapshot(address /* account */ )
        external
        view
        virtual
        override
        returns (uint256, uint256, uint256, uint256)
    {
        return (0, 0, 0, 0);
    }

    function getCash() external view virtual override returns (uint256) {
        return IERC20(underlying).balanceOf(address(this));
    } // Return mock's balance

    function seize(address, /* liquidator */ address, /* borrower */ uint256 /* seizeTokens */ )
        external
        virtual
        override
        returns (uint256)
    {
        return 0;
    }

    function supplyRatePerBlock() external view virtual override returns (uint256) {
        return 0;
    }

    function totalBorrowsCurrent() external virtual override returns (uint256) {
        this.accrueInterest();
        return totalBorrows;
    } // Match CErc20Delegator behavior

    function transfer(address dst, uint256 amount) external virtual override returns (bool) {
        cTokenBalances[msg.sender] -= amount;
        cTokenBalances[dst] += amount;
        emit Transfer(msg.sender, dst, amount);
        return true;
    }

    function transferFrom(address src, address dst, uint256 amount) external virtual override returns (bool) {
        cTokenBalances[src] -= amount;
        cTokenBalances[dst] += amount;
        emit Transfer(src, dst, amount);
        return true;
    } // Simplified: Ignores allowance for mock

    // --- Added Minimal Implementations for CErc20Interface (implicitly required) ---
    // These are defined in CErc20Interface which CTokenInterface inherits storage from,
    // but the functions themselves are often implemented in the delegator/delegate pattern.
    // We need them here because MockCToken directly inherits CTokenInterface.

    function borrow(uint256 /* borrowAmount */ ) external virtual override(CErc20Interface) returns (uint256) {
        return 0;
    } // Added override specifier

    function repayBorrow(uint256 /* repayAmount */ ) external virtual override(CErc20Interface) returns (uint256) {
        return 0;
    } // Added override specifier

    function repayBorrowBehalf(address, /* borrower */ uint256 /* repayAmount */ )
        external
        virtual
        override(CErc20Interface)
        returns (uint256)
    {
        return 0;
    } // Added override specifier

    function liquidateBorrow(address, /* borrower */ uint256, /* repayAmount */ CTokenInterface /* cTokenCollateral */ )
        external
        virtual
        override(CErc20Interface)
        returns (uint256)
    {
        return 0;
    } // Added override specifier

    function sweepToken(EIP20NonStandardInterface /* token */ ) external virtual override(CErc20Interface) {} // Added override specifier

    function _addReserves(uint256 /* addAmount */ ) external virtual override(CErc20Interface) returns (uint256) {
        return 0;
    } // Added override specifier
}
