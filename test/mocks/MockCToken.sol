// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SimpleMockCToken} from "../../src/mocks/SimpleMockCToken.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

contract MockCToken is SimpleMockCToken {
    constructor(
        address underlyingAddress_,
        address comptrollerAddress_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    )
        SimpleMockCToken(
            underlyingAddress_,
            ComptrollerInterface(comptrollerAddress_),
            InterestRateModel(address(0)), // Mock interest rate model
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            decimals_,
            payable(msg.sender)
        )
    {}

    function setExchangeRateForTesting(uint256 newRate) external {
        this.setExchangeRate(newRate);
    }

    function simulateInterestAccrual(uint256 newBorrowIndex) external {
        borrowIndex = newBorrowIndex;
        accrualBlockNumber = block.number;
    }

    function addReservesForTesting(uint256 amount) external {
        totalReserves += amount;
    }

    function setBorrowBalanceForTesting(address borrower, uint256 principal, uint256 interestIndex) external {
        accountBorrows[borrower].principal = principal;
        accountBorrows[borrower].interestIndex = interestIndex;
        totalBorrows += principal;
    }

    function getCashForTesting() external view returns (uint256) {
        return this.getCash();
    }

    function getTotalBorrowsForTesting() external view returns (uint256) {
        return totalBorrows;
    }

    function getTotalReservesForTesting() external view returns (uint256) {
        return totalReserves;
    }
}
