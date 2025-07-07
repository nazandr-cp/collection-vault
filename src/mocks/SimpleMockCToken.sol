// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// CTokenInterface inherits CTokenStorage. CErc20Interface inherits CErc20Storage.
import {
    CTokenInterface,
    CTokenStorage,
    CErc20Interface,
    CErc20Storage,
    ComptrollerInterface,
    InterestRateModel
} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {EIP20Interface} from "compound-protocol-2.8.1/contracts/EIP20Interface.sol";
import {EIP20NonStandardInterface} from "compound-protocol-2.8.1/contracts/EIP20NonStandardInterface.sol";
// import {ErrorReporter} from "compound-protocol-2.8.1/contracts/ErrorReporter.sol"; // For error codes if used

// Inherit from CTokenInterface and CErc20Interface ONLY.
// CTokenInterface includes ERC20-like function signatures and CTokenStorage.
// CErc20Interface includes CErc20-specific functions and CErc20Storage.
contract SimpleMockCToken is CTokenInterface, CErc20Interface {
    // Inherited public state variables from CTokenStorage via CTokenInterface:
    // string public name;
    // string public symbol;
    // uint8 public decimals;
    // address payable public admin;
    // address payable public pendingAdmin;
    // ComptrollerInterface public comptroller;
    // InterestRateModel public interestRateModel;
    // uint public reserveFactorMantissa;
    // uint public accrualBlockNumber;
    // uint public borrowIndex;
    // uint public totalBorrows;
    // uint public totalReserves;
    // uint public totalSupply; // This is CToken's total supply

    // Inherited internal state variables from CTokenStorage:
    // mapping (address => uint) internal accountTokens; // Balances
    // mapping (address => mapping (address => uint)) internal transferAllowances; // Allowances
    // mapping(address => BorrowSnapshot) internal accountBorrows;
    // bool internal _notEntered;
    // uint internal initialExchangeRateMantissa; // from CTokenStorage

    // Inherited public state variables from CErc20Storage via CErc20Interface:
    // address public underlying;

    // Custom state for mocking exchange rate
    uint256 internal mockExchangeRateMantissa;
    bool internal useMockExchangeRate;

    // Custom events for fees
    event NewAdminFee(uint256 oldAdminFeeMantissa, uint256 newAdminFeeMantissa);
    event NewComptrollerFee(uint256 oldComptrollerFeeMantissa, uint256 newComptrollerFeeMantissa);

    // Custom state variables for fees
    uint256 public adminFeeMantissa;
    uint256 public comptrollerFeeMantissa;

    constructor(
        address underlyingAddress_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address payable admin_
    ) {
        require(underlyingAddress_ != address(0), "Underlying cannot be zero address");
        require(admin_ != address(0), "Admin cannot be zero address");
        
        // Initialize CTokenStorage public state variables directly
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        admin = admin_;
        pendingAdmin = payable(address(0));
        comptroller = comptroller_;
        interestRateModel = interestRateModel_;
        initialExchangeRateMantissa = initialExchangeRateMantissa_;
        reserveFactorMantissa = 0;
        accrualBlockNumber = block.number;
        borrowIndex = 1e18;
        totalBorrows = 0;
        totalReserves = 0;
        totalSupply = 0;

        // Initialize CErc20Storage members
        underlying = underlyingAddress_;

        _notEntered = true;
        useMockExchangeRate = false; // Initialize mock rate flag
    }

    // --- ERC20-like functions required by CTokenInterface ---
    // The public state variables name, symbol, decimals, totalSupply
    // from CTokenStorage automatically create getter functions that satisfy
    // the CTokenInterface requirements. We do not need to re-declare them.

    function balanceOf(address owner) public view virtual override returns (uint256) {
        return accountTokens[owner];
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return transferAllowances[owner][spender];
    }

    function transfer(address dst, uint256 amount) public virtual override returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    function transferFrom(address src, address dst, uint256 amount) public virtual override returns (bool) {
        address spender = msg.sender;
        uint256 currentAllowance = transferAllowances[src][spender];
        require(currentAllowance >= amount, "CToken: transfer amount exceeds allowance");

        if (currentAllowance != type(uint256).max) {
            transferAllowances[src][spender] = currentAllowance - amount;
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        transferAllowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount); // Event from CTokenInterface
        return true;
    }

    // Internal token management functions
    function _transferTokens(address src, address dst, uint256 amount) internal {
        require(src != address(0), "CToken: transfer from the zero address");
        require(dst != address(0), "CToken: transfer to the zero address");
        require(accountTokens[src] >= amount, "CToken: transfer amount exceeds balance");

        accountTokens[src] -= amount;
        accountTokens[dst] += amount;

        emit Transfer(src, dst, amount); // Event from CTokenInterface
    }

    function _mintTokens(address minter, uint256 amount) internal {
        require(minter != address(0), "CToken: mint to the zero address");
        totalSupply += amount; // Directly use inherited state variable
        accountTokens[minter] += amount;
        // No explicit Transfer event here, as mint() should emit its own Mint event
    }

    function _burnTokens(address burner, uint256 amount) internal {
        require(burner != address(0), "CToken: burn from the zero address");
        require(accountTokens[burner] >= amount, "CToken: burn amount exceeds balance");

        accountTokens[burner] -= amount;
        totalSupply -= amount; // Directly use inherited state variable
            // No explicit Transfer event here, as redeem() should emit its own Redeem event
    }

    // --- CTokenInterface & CErc20Interface implementations ---

    function mint(uint256 mintAmount) external virtual override returns (uint256) {
        uint256 cTokensToMint = mintAmount; // Simplified: 1 underlying = 1 cToken for mock
        require(EIP20Interface(underlying).transferFrom(msg.sender, address(this), mintAmount), "Transfer failed"); // Mock transfer
        _mintTokens(msg.sender, cTokensToMint);
        emit Mint(msg.sender, mintAmount, cTokensToMint);
        return 0; // Represents Error.NO_ERROR
    }

    function redeem(uint256 redeemCTokens) external virtual override returns (uint256) {
        uint256 underlyingAmountToReturn = redeemCTokens; // Simplified
        _burnTokens(msg.sender, redeemCTokens);
        require(EIP20Interface(underlying).transfer(msg.sender, underlyingAmountToReturn), "Transfer failed"); // Mock transfer
        emit Redeem(msg.sender, underlyingAmountToReturn, redeemCTokens);
        return 0;
    }

    function redeemUnderlying(uint256 redeemAmount) external virtual override returns (uint256) {
        uint256 cTokensToBurn = redeemAmount; // Simplified
        _burnTokens(msg.sender, cTokensToBurn);
        require(EIP20Interface(underlying).transfer(msg.sender, redeemAmount), "Transfer failed"); // Mock transfer
        emit Redeem(msg.sender, redeemAmount, cTokensToBurn);
        return 0;
    }

    function borrow(uint256 borrowAmount) external virtual override returns (uint256) {
        CTokenStorage.totalBorrows += borrowAmount;
        accountBorrows[msg.sender].principal += borrowAmount;
        accountBorrows[msg.sender].interestIndex = borrowIndex;
        require(EIP20Interface(underlying).transfer(msg.sender, borrowAmount), "Transfer failed"); // Mock transfer
        emit Borrow(msg.sender, borrowAmount, accountBorrows[msg.sender].principal, CTokenStorage.totalBorrows);
        return 0;
    }

    function repayBorrow(uint256 repayAmount) external virtual override returns (uint256) {
        require(EIP20Interface(underlying).transferFrom(msg.sender, address(this), repayAmount), "Transfer failed"); // Mock transfer
        uint256 borrowed = accountBorrows[msg.sender].principal;
        uint256 actualRepayAmount = repayAmount > borrowed ? borrowed : repayAmount;
        CTokenStorage.totalBorrows -= actualRepayAmount;
        accountBorrows[msg.sender].principal -= actualRepayAmount;
        emit RepayBorrow(
            msg.sender, msg.sender, actualRepayAmount, accountBorrows[msg.sender].principal, CTokenStorage.totalBorrows
        );
        return 0;
    }

    function repayBorrowBehalf(address borrower, uint256 repayAmount) external virtual override returns (uint256) {
        require(EIP20Interface(underlying).transferFrom(msg.sender, address(this), repayAmount), "Transfer failed"); // Mock transfer
        uint256 borrowed = accountBorrows[borrower].principal;
        uint256 actualRepayAmount = repayAmount > borrowed ? borrowed : repayAmount;
        CTokenStorage.totalBorrows -= actualRepayAmount;
        accountBorrows[borrower].principal -= actualRepayAmount;
        emit RepayBorrow(
            msg.sender, borrower, actualRepayAmount, accountBorrows[borrower].principal, CTokenStorage.totalBorrows
        );
        return 0;
    }

    function liquidateBorrow(address borrower, uint256 repayAmount, CTokenInterface cTokenCollateral)
        external
        virtual
        override
        returns (uint256)
    {
        revert("SimpleMockCToken: liquidateBorrow not implemented");
    }

    function sweepToken(EIP20NonStandardInterface token) external virtual override {
        revert("SimpleMockCToken: sweepToken not implemented");
    }

    function balanceOfUnderlying(address owner) external virtual override returns (uint256) {
        uint256 cTokenBalance = accountTokens[owner];
        uint256 currentExchangeRate = this.exchangeRateStored();
        if (CTokenStorage.totalSupply == 0 || currentExchangeRate == 0) return 0;
        return cTokenBalance * currentExchangeRate / 1e18;
    }

    function getAccountSnapshot(address account)
        external
        view
        virtual
        override
        returns (uint256, uint256, uint256, uint256)
    {
        return (accountTokens[account], accountBorrows[account].principal, this.exchangeRateStored(), 0);
    }

    function borrowRatePerBlock() external view virtual override returns (uint256) {
        // return interestRateModel.getBorrowRate(this.getCash(), CTokenStorage.totalBorrows, CTokenStorage.totalReserves);
        return 0; // Simplified mock
    }

    function supplyRatePerBlock() external view virtual override returns (uint256) {
        // return interestRateModel.getSupplyRate(this.getCash(), CTokenStorage.totalBorrows, CTokenStorage.totalReserves, reserveFactorMantissa);
        return 0; // Simplified mock
    }

    function totalBorrowsCurrent() external virtual override returns (uint256) {
        // this.accrueInterest(); // In a real contract
        return CTokenStorage.totalBorrows;
    }

    function borrowBalanceCurrent(address account) external virtual override returns (uint256) {
        // this.accrueInterest(); // In a real contract
        return accountBorrows[account].principal; // Simplified for mock
    }

    function borrowBalanceStored(address account) external view virtual override returns (uint256) {
        return accountBorrows[account].principal;
    }

    function exchangeRateCurrent() external virtual override returns (uint256) {
        // this.accrueInterest(); // In a real contract
        return this.exchangeRateStored();
    }

    function exchangeRateStored() external view virtual override returns (uint256) {
        if (useMockExchangeRate) {
            return mockExchangeRateMantissa;
        }
        if (CTokenStorage.totalSupply == 0) {
            return CTokenStorage.initialExchangeRateMantissa;
        }
        uint256 cash = this.getCash();
        uint256 _totalSupply = CTokenStorage.totalSupply;
        uint256 _totalBorrows = CTokenStorage.totalBorrows;
        uint256 _totalReserves = CTokenStorage.totalReserves;

        // This check is redundant as it's covered by the first check in this function
        // if (_totalSupply == 0) return CTokenStorage.initialExchangeRateMantissa;

        uint256 numerator;
        if (_totalBorrows >= _totalReserves) {
            numerator = (cash + _totalBorrows - _totalReserves);
        } else {
            numerator = cash > (_totalReserves - _totalBorrows) ? cash - (_totalReserves - _totalBorrows) : 0;
        }
        if (_totalSupply == 0) return CTokenStorage.initialExchangeRateMantissa; // Safety for division by zero if logic changes
        return numerator * 1e18 / _totalSupply;
    }

    // --- Mock specific functions ---
    /**
     * @notice Sets a mock exchange rate for testing purposes.
     * @dev This will override the dynamic calculation in exchangeRateStored().
     * @param newRateMantissa The new exchange rate mantissa (scaled by 1e18, like initialExchangeRateMantissa).
     */
    function setExchangeRate(uint256 newRateMantissa) external {
        // In a real scenario, only admin or specific roles might call this. For a mock, it's open.
        mockExchangeRateMantissa = newRateMantissa;
        useMockExchangeRate = true;
    }

    /**
     * @notice Resets the exchange rate to be dynamically calculated.
     */
    function resetExchangeRateToDynamic() external {
        useMockExchangeRate = false;
    }

    function getCash() external view virtual override returns (uint256) {
        if (underlying == address(0)) return 0; // Handle case where underlying might not be set (e.g. cEther)
        return EIP20Interface(underlying).balanceOf(address(this));
    }

    function accrueInterest() external virtual override returns (uint256) {
        emit AccrueInterest(this.getCash(), 0, borrowIndex, CTokenStorage.totalBorrows);
        return 0;
    }

    function seize(address liquidator, address borrower, uint256 seizeTokens)
        external
        virtual
        override
        returns (uint256)
    {
        revert("SimpleMockCToken: seize not implemented");
    }

    // --- Admin Functions (from CTokenInterface) ---
    function _setPendingAdmin(address payable newPendingAdmin) external virtual override returns (uint256) {
        require(msg.sender == admin, "CToken: sender must be admin");
        require(newPendingAdmin != address(0), "New pending admin cannot be zero address");
        address oldPendingAdmin = pendingAdmin;
        pendingAdmin = newPendingAdmin;
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);
        return 0;
    }

    function _acceptAdmin() external virtual override returns (uint256) {
        require(
            msg.sender == pendingAdmin && msg.sender != address(0),
            "CToken: sender must be pendingAdmin and not zero address"
        );
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;
        admin = pendingAdmin;
        pendingAdmin = payable(address(0));
        emit NewAdmin(oldAdmin, admin);
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);
        return 0;
    }

    function _setComptroller(ComptrollerInterface newComptroller) external virtual override returns (uint256) {
        require(msg.sender == admin, "CToken: sender must be admin");
        ComptrollerInterface oldComptroller = comptroller;
        comptroller = newComptroller;
        emit NewComptroller(oldComptroller, newComptroller);
        return 0;
    }

    function _setReserveFactor(uint256 newReserveFactorMantissa) external virtual override returns (uint256) {
        require(msg.sender == admin, "CToken: sender must be admin");
        require(newReserveFactorMantissa <= 1e18, "CToken: invalid reserve factor"); // Max is 100% (1e18)
        uint256 oldReserveFactorMantissa = reserveFactorMantissa;
        reserveFactorMantissa = newReserveFactorMantissa;
        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);
        return 0;
    }

    function _reduceReserves(uint256 reduceAmount) external virtual override returns (uint256) {
        require(msg.sender == admin, "CToken: sender must be admin");
        require(reduceAmount <= CTokenStorage.totalReserves, "CToken: reduce amount exceeds total reserves");
        CTokenStorage.totalReserves -= reduceAmount;
        // EIP20Interface(underlying).transfer(admin, reduceAmount); // Mock transfer
        emit ReservesReduced(admin, reduceAmount, CTokenStorage.totalReserves);
        return 0;
    }

    function _setInterestRateModel(InterestRateModel newInterestRateModel)
        external
        virtual
        override
        returns (uint256)
    {
        require(msg.sender == admin, "CToken: sender must be admin");
        InterestRateModel oldInterestRateModel = interestRateModel;
        interestRateModel = newInterestRateModel;
        emit NewMarketInterestRateModel(oldInterestRateModel, newInterestRateModel);
        return 0;
    }

    // --- Admin Functions (from CErc20Interface) ---
    function _addReserves(uint256 addAmount) external virtual override returns (uint256) {
        require(msg.sender != address(0) && addAmount > 0, "CToken: invalid input for add reserves");
        // EIP20Interface(underlying).transferFrom(msg.sender, address(this), addAmount); // Mock transfer
        CTokenStorage.totalReserves += addAmount;
        emit ReservesAdded(msg.sender, addAmount, CTokenStorage.totalReserves);
        return 0;
    }

    // --- Custom fee functions ---
    function _setAdminFee(uint256 newAdminFeeMantissa) external returns (uint256) {
        require(msg.sender == admin, "SimpleMockCToken: sender must be admin to set admin fee");
        uint256 oldAdminFeeMantissa = adminFeeMantissa;
        adminFeeMantissa = newAdminFeeMantissa;
        emit NewAdminFee(oldAdminFeeMantissa, newAdminFeeMantissa);
        return 0;
    }

    function _setComptrollerFee(uint256 newComptrollerFeeMantissa) external returns (uint256) {
        require(msg.sender == admin, "SimpleMockCToken: sender must be admin to set comptroller fee");
        uint256 oldComptrollerFeeMantissa = comptrollerFeeMantissa;
        comptrollerFeeMantissa = newComptrollerFeeMantissa;
        emit NewComptrollerFee(oldComptrollerFeeMantissa, newComptrollerFeeMantissa);
        return 0;
    }
}
