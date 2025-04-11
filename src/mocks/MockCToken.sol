// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MinimalCTokenInterface} from "../interfaces/MinimalCTokenInterface.sol";
import {IERC20} from "@openzeppelin-contracts-5.2.0/token/ERC20/IERC20.sol";

/**
 * @title MockCToken
 * @notice Mock for Compound cToken interactions in LendingManager tests.
 */
contract MockCToken is MinimalCTokenInterface {
    IERC20 public immutable underlyingToken;
    string public name = "Mock cToken";
    string public symbol = "mcTOK";
    uint8 public constant DECIMALS = 8; // Compound standard

    uint256 public currentExchangeRate = 0.02e18; // Example initial rate (scaled)
    mapping(address => uint256) public cTokenBalances;
    mapping(address => uint256) public underlyingBalances; // Track underlying held "in" cToken

    uint256 public mintResult = 0; // 0 for success
    uint256 public redeemResult = 0; // 0 for success

    event MockMint(address minter, uint256 mintAmount, uint256 mintTokens);
    event MockRedeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    constructor(address _underlying) {
        underlyingToken = IERC20(_underlying);
    }

    // --- Mock Control Functions ---
    function setExchangeRate(uint256 _rate) external {
        currentExchangeRate = _rate;
    }

    function setMintResult(uint256 _result) external {
        mintResult = _result;
    }

    function setRedeemResult(uint256 _result) external {
        redeemResult = _result;
    }

    function setUnderlyingBalance(address owner, uint256 amount) external {
        underlyingBalances[owner] = amount;
    }

    // --- MinimalCTokenInterface Implementation ---
    function mint(uint256 mintAmount) external override returns (uint256) {
        if (mintResult != 0) return mintResult;

        // Simulate pulling underlying from caller (LendingManager)
        underlyingToken.transferFrom(msg.sender, address(this), mintAmount);

        // Update internal tracking
        underlyingBalances[msg.sender] += mintAmount;

        // Calculate cTokens to mint (simplified)
        uint256 cTokensToMint = (mintAmount * 1e18) / currentExchangeRate; // Inverse of underlying calc
        cTokenBalances[msg.sender] += cTokensToMint;

        emit MockMint(msg.sender, mintAmount, cTokensToMint);
        return 0; // Success
    }

    function redeemUnderlying(uint256 redeemUnderlyingAmount) external override returns (uint256) {
        if (redeemResult != 0) return redeemResult;

        // Check if sender has enough underlying value
        uint256 currentUnderlying = balanceOfUnderlying(msg.sender);
        require(currentUnderlying >= redeemUnderlyingAmount, "MockCToken: Insufficient balance");

        // Calculate cTokens to burn
        uint256 cTokensToBurn = (redeemUnderlyingAmount * 1e18) / currentExchangeRate;
        require(cTokenBalances[msg.sender] >= cTokensToBurn, "MockCToken: Insufficient cTokens");

        // Update balances
        cTokenBalances[msg.sender] -= cTokensToBurn;
        underlyingBalances[msg.sender] -= redeemUnderlyingAmount;

        // Simulate sending underlying back to caller
        underlyingToken.transfer(msg.sender, redeemUnderlyingAmount);

        emit MockRedeem(msg.sender, redeemUnderlyingAmount, cTokensToBurn);
        return 0; // Success
    }

    function balanceOfUnderlying(address owner) public view override returns (uint256) {
        // Revert to original simple implementation for now, as LM doesn't use it.
        return underlyingBalances[owner];
        /* // Formula calculation - keep commented out as it wasn't the fix needed
        uint256 cTokenBalance = cTokenBalances[owner];
        if (cTokenBalance == 0) return 0;
        uint256 exRate = currentExchangeRate;
        if (exRate == 0) return 0;
        return (cTokenBalance * exRate) / 1e18;
        */
    }

    function underlying() external view override returns (address) {
        return address(underlyingToken);
    }

    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    function exchangeRateStored() external view override returns (uint256) {
        // This should be scaled: 1e(18 + underlyingDecimals - cTokenDecimals)
        // uint8 underlyingDecimals = IERC20(underlyingToken).decimals();
        // return currentExchangeRate * (10**(18 + underlyingDecimals - DECIMALS));
        return currentExchangeRate; // Return the raw rate for simplicity in mock
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return cTokenBalances[owner];
    }
}
