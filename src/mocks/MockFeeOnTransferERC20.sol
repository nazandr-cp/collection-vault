// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public globalFeeBps; // Basis points, e.g., 100 for 1%
    uint8 private _customDecimals;
    address public feeCollector; // Made mutable for flexibility if needed, though constructor sets it

    mapping(address => uint256) public accountSpecificReceiveFeeBps;
    mapping(address => bool) public hasAccountSpecificReceiveFeeBps;

    event FeeCharged(
        address indexed from,
        address indexed to,
        address indexed feeCollector,
        uint256 feeAmount,
        uint256 actualFeeBpsUsed
    );
    event GlobalFeeBpsSet(uint256 newFeeBps);
    event AccountReceiveFeeBpsSet(address indexed account, uint256 feeBps);
    event AccountReceiveFeeBpsCleared(address indexed account);

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupplyToDeployer, // Amount in token units, e.g., 1000 tokens
        uint256 _initialGlobalFeeBps,
        address _feeCollector
    ) ERC20(name, symbol) {
        _customDecimals = decimals_;

        require(_feeCollector != address(0), "FeeCollector cannot be zero address");
        require(_initialGlobalFeeBps <= 10000, "Fee cannot exceed 100% (10000 bps)");

        globalFeeBps = _initialGlobalFeeBps;
        feeCollector = _feeCollector;

        if (initialSupplyToDeployer > 0) {
            _mint(msg.sender, initialSupplyToDeployer * (10 ** uint256(_customDecimals)));
        }
    }

    function _getApplicableFeeBps(address from, address to) internal view returns (uint256) {
        if (hasAccountSpecificReceiveFeeBps[to]) {
            return accountSpecificReceiveFeeBps[to];
        }
        // Add sender-specific fee logic here if needed in the future
        // if (hasAccountSpecificSendFeeBps[from]) {
        //     return accountSpecificSendFeeBps[from];
        // }
        return globalFeeBps;
    }

    /// @dev Overrides the internal _update function to apply fees.
    function _update(address from, address to, uint256 value) internal virtual override {
        if (from == address(0) || to == address(0) || value == 0) {
            // Minting, burning, or zero-value transfer. No fees applied by this logic.
            super._update(from, to, value);
            return;
        }

        uint256 currentFeeBps = _getApplicableFeeBps(from, to);
        uint256 fee = 0;
        uint256 amountToRecipient = value; // Initialize amountToRecipient with the full value

        if (currentFeeBps > 0) {
            fee = (value * currentFeeBps) / 10000;
            if (fee > value) fee = value; // Fee cannot exceed value
            amountToRecipient = value - fee; // Recalculate amountToRecipient if there's a fee
        }

        // Now amountToRecipient is correctly set (either original value or value - fee)
        // The OpenZeppelin _update function handles debiting the `from` account and crediting the `to` account.
        // We need two such operations if a fee is involved:
        // 1. Transfer `amountToRecipient` from `from` to `to`.
        // 2. Transfer `fee` from `from` to `feeCollector`.

        if (amountToRecipient > 0) {
            super._update(from, to, amountToRecipient);
        }

        if (fee > 0) {
            super._update(from, feeCollector, fee);
            emit FeeCharged(from, to, feeCollector, fee, currentFeeBps); // `to` is the original intended recipient
        }
        // If value > 0, but fee is 100% (currentFeeBps = 10000), then amountToRecipient is 0.
        // In this case, only the fee transfer happens.
        // If currentFeeBps is 0, then fee is 0, amountToRecipient is value. Only main transfer happens.
        // If value is 0, the initial check `value == 0` handles it.
        // The old `if (amountToRecipient == 0 && fee == 0 && value > 0)` block is no longer needed
        // as super._update(from, to, 0) is a no-op and covered by the conditions above.
    }

    function decimals() public view virtual override returns (uint8) {
        return _customDecimals;
    }

    function mint(address account, uint256 amount) public {
        // Scale the amount by decimals before minting
        _mint(account, amount * (10 ** uint256(_customDecimals)));
    }

    function burn(address account, uint256 amount) public {
        // Scale the amount by decimals before burning
        _burn(account, amount * (10 ** uint256(_customDecimals)));
    }

    function setGlobalFeeBps(uint16 newFeeBps) public {
        require(newFeeBps <= 10000, "Fee cannot exceed 100%");
        globalFeeBps = newFeeBps;
        emit GlobalFeeBpsSet(newFeeBps);
    }

    function setFeeBpsReceive(address account, uint16 feeBps_) public {
        require(feeBps_ <= 10000, "Fee cannot exceed 100%");
        require(account != address(0), "Cannot set fee for zero address");
        accountSpecificReceiveFeeBps[account] = feeBps_;
        hasAccountSpecificReceiveFeeBps[account] = true;
        emit AccountReceiveFeeBpsSet(account, feeBps_);
    }

    function clearFeeBpsReceive(address account) public {
        require(account != address(0), "Cannot clear fee for zero address");
        hasAccountSpecificReceiveFeeBps[account] = false;
        // Optionally zero out accountSpecificReceiveFeeBps[account] too
        // delete accountSpecificReceiveFeeBps[account]; // This is implicit for bool false
        emit AccountReceiveFeeBpsCleared(account);
    }

    // Keep setFeeBps for backward compatibility if some tests used it, make it alias to setGlobalFeeBps
    // This also addresses the previous comments about immutability, as globalFeeBps is now mutable.
    function setFeeBps(uint16 newFeeBps) public {
        setGlobalFeeBps(newFeeBps);
    }
}
