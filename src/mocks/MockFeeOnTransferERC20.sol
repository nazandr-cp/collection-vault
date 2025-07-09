// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockFeeOnTransferERC20 is ERC20 {
    uint16 public feeBpsSend; // Fee basis points for sending tokens
    uint16 public feeBpsReceive; // Fee basis points for receiving tokens
    address public feeCollector;
    uint8 private _mockDecimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_, // Renamed to avoid conflict with function
        uint16 _feeBpsSend,
        uint16 _feeBpsReceive,
        address _feeCollector
    ) ERC20(name, symbol) {
        require(_feeCollector != address(0), "Fee collector cannot be zero address");
        require(_feeBpsSend <= 10000 && _feeBpsReceive <= 10000, "Fee too high");

        _mockDecimals = decimals_; // Store decimals
        feeBpsSend = _feeBpsSend;
        feeBpsReceive = _feeBpsReceive;
        feeCollector = _feeCollector;
    }

    function decimals() public view virtual override returns (uint8) {
        return _mockDecimals;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0)) {
            // Minting
            super._update(from, to, value);
            return;
        }

        if (to == address(0)) {
            // Burning
            super._update(from, to, value);
            return;
        }

        uint256 valueAfterTax = value;
        uint256 feeAmountSend = 0;
        uint256 feeAmountReceive = 0;

        if (feeBpsSend > 0 && from != feeCollector) {
            feeAmountSend = (value * feeBpsSend) / 10000;
            if (feeAmountSend > 0) {
                super._update(from, feeCollector, feeAmountSend);
            }
            valueAfterTax -= feeAmountSend;
        }

        // The receiver gets less if there's a receive fee,
        // but the sender still sends the full `valueAfterTax` (after send fee).
        // The `valueAfterTax` is what the `to` address *would* receive before receive fee.
        if (feeBpsReceive > 0 && to != feeCollector) {
            feeAmountReceive = (valueAfterTax * feeBpsReceive) / 10000; // Calculate fee on amount intended for receiver
            if (feeAmountReceive > 0) {
                super._update(from, feeCollector, feeAmountReceive); // Sender pays this fee too
            }
            // The actual amount received by 'to' is reduced by feeAmountReceive
            // but the transfer from 'from' must account for the original valueAfterTax *minus* the receive fee.
            // This is tricky. Let's simplify: the sender sends `valueAfterTax`, and `to` receives `valueAfterTax - feeAmountReceive`.
            // The `feeAmountReceive` is taken from the `valueAfterTax` that was supposed to go to `to`.
            // So, `from` transfers `valueAfterTax` in total. `to` gets `valueAfterTax - feeAmountReceive`. `feeCollector` gets `feeAmountReceive`.
            // This means `from` must be debited `valueAfterTax`.
            // `to` is credited `valueAfterTax - feeAmountReceive`.
            // `feeCollector` is credited `feeAmountReceive`.
            // The super._update below handles the transfer from `from` to `to`.
            // We need to ensure `from` has enough for `valueAfterTax` and `to` receives the reduced amount.
            // The current logic for `super._update(from, to, valueAfterTax - feeAmountReceive)` is correct for the `to` balance.
            // The `super._update(from, feeCollector, feeAmountSend)` and `super._update(from, feeCollector, feeAmountReceive)`
            // correctly debit `from` for the fees.
            // The final `super._update(from, to, ...)` debits `from` for the amount sent to `to`.
        }

        if (valueAfterTax - feeAmountReceive > 0) {
            super._update(from, to, valueAfterTax - feeAmountReceive);
        }
    }

    function setFeeBpsSend(uint16 _newFeeBps) external {
        require(_newFeeBps <= 10000, "Fee too high");
        feeBpsSend = _newFeeBps;
    }

    function setFeeBpsReceive(uint16 _newFeeBps) external {
        require(_newFeeBps <= 10000, "Fee too high");
        feeBpsReceive = _newFeeBps;
    }

    function setFeeCollector(address _newFeeCollector) external {
        require(_newFeeCollector != address(0), "Fee collector cannot be zero address");
        feeCollector = _newFeeCollector;
    }
}
