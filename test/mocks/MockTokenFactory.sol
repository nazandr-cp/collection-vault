// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MockERC20} from "./MockERC20.sol";
import {MockERC721} from "./MockERC721.sol";
import {MockCToken} from "./MockCToken.sol";
import {MockComptroller} from "./MockComptroller.sol";

contract MockTokenFactory {
    event TokenCreated(string tokenType, address tokenAddress, string name, string symbol);

    function createERC20(string memory name, string memory symbol, uint8 decimals, uint256 initialSupply)
        external
        returns (MockERC20)
    {
        MockERC20 token = new MockERC20(name, symbol, decimals, initialSupply);
        emit TokenCreated("ERC20", address(token), name, symbol);
        return token;
    }

    function createERC721(string memory name, string memory symbol) external returns (MockERC721) {
        MockERC721 token = new MockERC721(name, symbol);
        emit TokenCreated("ERC721", address(token), name, symbol);
        return token;
    }

    function createCToken(
        address underlyingAddress,
        address comptrollerAddress,
        uint256 initialExchangeRateMantissa,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external returns (MockCToken) {
        MockCToken cToken =
            new MockCToken(underlyingAddress, comptrollerAddress, initialExchangeRateMantissa, name, symbol, decimals);
        emit TokenCreated("CToken", address(cToken), name, symbol);
        return cToken;
    }

    function createComptroller() external returns (MockComptroller) {
        MockComptroller comptroller = new MockComptroller();
        emit TokenCreated("Comptroller", address(comptroller), "MockComptroller", "COMP");
        return comptroller;
    }
}
