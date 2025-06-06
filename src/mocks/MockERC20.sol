// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @notice Basic ERC20 token mock for testing.
 */
contract MockERC20 is ERC20, Ownable {
    uint8 internal _customDecimals;

    constructor(string memory name, string memory symbol, uint8 decimals_, uint256 initialSupply)
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        _customDecimals = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // function _transfer(address from, address to, uint256 value) internal virtual override {
    //     super._transfer(from, to, value);
    // }
    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }
}
