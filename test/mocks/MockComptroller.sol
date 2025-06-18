// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ComptrollerInterface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";

contract MockComptroller is ComptrollerInterface {
    mapping(address => bool) public marketListed;
    mapping(address => uint256) public collateralFactorMantissa;

    uint256 public closeFactor = 0.5e18; // 50%
    uint256 public liquidationIncentive = 1.08e18; // 8% incentive

    constructor() {
        // Default allow all operations for testing
    }

    function enterMarkets(address[] calldata cTokens) external override returns (uint256[] memory) {
        uint256[] memory results = new uint256[](cTokens.length);
        for (uint256 i = 0; i < cTokens.length; i++) {
            results[i] = 0; // Success
        }
        return results;
    }

    function exitMarket(address cToken) external override returns (uint256) {
        return 0; // Success
    }

    function mintAllowed(address cToken, address minter, uint256 mintAmount) external override returns (uint256) {
        return 0; // Success
    }

    function mintVerify(address cToken, address minter, uint256 actualMintAmount, uint256 mintTokens)
        external
        override
    {
        // No verification needed in mock
    }

    function redeemAllowed(address cToken, address redeemer, uint256 redeemTokens)
        external
        override
        returns (uint256)
    {
        return 0; // Success
    }

    function redeemVerify(address cToken, address redeemer, uint256 redeemAmount, uint256 redeemTokens)
        external
        override
    {
        // No verification needed in mock
    }

    function borrowAllowed(address cToken, address borrower, uint256 borrowAmount)
        external
        override
        returns (uint256)
    {
        return 0; // Success
    }

    function borrowVerify(address cToken, address borrower, uint256 borrowAmount) external override {
        // No verification needed in mock
    }

    function repayBorrowAllowed(address cToken, address payer, address borrower, uint256 repayAmount)
        external
        override
        returns (uint256)
    {
        return 0; // Success
    }

    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint256 actualRepayAmount,
        uint256 borrowerIndex
    ) external override {
        // No verification needed in mock
    }

    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external override returns (uint256) {
        return 0; // Success
    }

    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint256 actualRepayAmount,
        uint256 seizeTokens
    ) external override {
        // No verification needed in mock
    }

    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override returns (uint256) {
        return 0; // Success
    }

    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external override {
        // No verification needed in mock
    }

    function transferAllowed(address cToken, address src, address dst, uint256 transferTokens)
        external
        override
        returns (uint256)
    {
        return 0; // Success
    }

    function transferVerify(address cToken, address src, address dst, uint256 transferTokens) external override {
        // No verification needed in mock
    }

    function liquidateCalculateSeizeTokens(address cTokenBorrowed, address cTokenCollateral, uint256 actualRepayAmount)
        external
        view
        override
        returns (uint256, uint256)
    {
        // Simplified calculation for mock
        uint256 seizeTokens = actualRepayAmount * liquidationIncentive / 1e18;
        return (0, seizeTokens); // (error, seizeTokens)
    }

    // Admin functions
    function _supportMarket(address cToken) external returns (uint256) {
        marketListed[cToken] = true;
        return 0;
    }

    function _setCollateralFactor(address cToken, uint256 newCollateralFactorMantissa) external returns (uint256) {
        collateralFactorMantissa[cToken] = newCollateralFactorMantissa;
        return 0;
    }

    function _setCloseFactor(uint256 newCloseFactorMantissa) external returns (uint256) {
        closeFactor = newCloseFactorMantissa;
        return 0;
    }

    function _setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external returns (uint256) {
        liquidationIncentive = newLiquidationIncentiveMantissa;
        return 0;
    }

    // View functions
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256) {
        // Return mock liquidity values (error, excess liquidity, shortfall)
        return (0, 1000e18, 0);
    }

    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256, uint256) {
        // Return mock liquidity values
        return (0, 1000e18, 0);
    }

    function checkMembership(address account, address cToken) external view returns (bool) {
        return true; // Mock: always member
    }

    function getAllMarkets() external view returns (address[] memory) {
        address[] memory markets = new address[](0);
        return markets;
    }

    function getAssetsIn(address account) external view returns (address[] memory) {
        address[] memory assets = new address[](0);
        return assets;
    }
}
