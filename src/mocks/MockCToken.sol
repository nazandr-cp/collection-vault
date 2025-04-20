// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MinimalCTokenInterface} from "../interfaces/MinimalCTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockCToken
 * @notice Mock for Compound cToken interactions in LendingManager tests.
 */
contract MockCToken is MinimalCTokenInterface {
    IERC20 public immutable underlyingToken;
    string public name = "Mock cToken";
    string public symbol = "mcTOK";
    uint8 public constant DECIMALS = 8;
    uint8 public constant UNDERLYING_DECIMALS = 18; // Assuming underlying is DAI
    uint256 private constant EXCHANGE_RATE_SCALE = 1 * 10 ** (18 + UNDERLYING_DECIMALS - DECIMALS); // 1e28

    // Stored rate should be scaled: 0.02 * 1e28 = 2e26
    uint256 public currentExchangeRate = 2 * 10 ** (18 + UNDERLYING_DECIMALS - DECIMALS - 2); // 2e26
    mapping(address => uint256) public cTokenBalances;

    uint256 public mintResult = 0;
    uint256 public redeemResult = 0;

    event MockMint(address minter, uint256 mintAmount, uint256 mintTokens);
    event MockRedeem(address redeemer, uint256 redeemAmount, uint256 redeemTokens);

    constructor(address _underlying) {
        underlyingToken = IERC20(_underlying);
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
    function mint(uint256 mintAmount) external override returns (uint256) {
        if (mintResult != 0) return mintResult;

        underlyingToken.transferFrom(msg.sender, address(this), mintAmount);

        // Calculate cTokens using scaled rate: cTokens = underlying * scale / rate
        uint256 cTokensToMint = mintAmount * EXCHANGE_RATE_SCALE / currentExchangeRate;
        cTokenBalances[msg.sender] += cTokensToMint;

        emit MockMint(msg.sender, mintAmount, cTokensToMint);
        return 0;
    }

    function redeemUnderlying(uint256 redeemUnderlyingAmount) external override returns (uint256) {
        if (redeemResult != 0) return redeemResult;

        // Calculate required cTokens using scaled rate: cTokens = underlying * scale / rate
        uint256 cTokensToBurn = redeemUnderlyingAmount * EXCHANGE_RATE_SCALE / currentExchangeRate;

        // Check if owner has enough cTokens
        require(cTokenBalances[msg.sender] >= cTokensToBurn, "MockCToken: Insufficient cTokens");

        // Check if this mock contract has enough underlying (simple check)
        require(
            underlyingToken.balanceOf(address(this)) >= redeemUnderlyingAmount, "MockCToken: Contract lacks underlying"
        );

        cTokenBalances[msg.sender] -= cTokensToBurn;
        underlyingToken.transfer(msg.sender, redeemUnderlyingAmount);

        emit MockRedeem(msg.sender, redeemUnderlyingAmount, cTokensToBurn);
        return 0;
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

    function underlying() external view override returns (address) {
        return address(underlyingToken);
    }

    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    function exchangeRateStored() external view override returns (uint256) {
        return currentExchangeRate;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return cTokenBalances[owner];
    }
}
