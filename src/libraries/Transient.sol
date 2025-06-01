// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Transient
 * @author Roo
 * @notice Provides EIP-1153 transient storage utilities for gas optimization.
 *         Allows for temporary state management during a single transaction's execution.
 *         Transient storage is cheaper than regular storage for data that does not
 *         need to persist across transactions.
 * @dev Uses `tstore` and `tload` assembly opcodes introduced in EIP-1153.
 *      Ensure the Solidity compiler version and EVM version (Shanghai or later) support these opcodes.
 */
library Transient {
    /**
     * @notice Stores a value in a transient storage slot.
     * @dev The slot is specific to the current transaction and call context.
     *      It does not persist across transactions.
     * @param slot The transient storage slot (uint256) to store the value in.
     *             Slots can be chosen arbitrarily, e.g., by hashing a unique identifier.
     * @param value The uint256 value to store.
     */
    function store(uint256 slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /**
     * @notice Loads a value from a transient storage slot.
     * @dev If the slot has not been written to in the current transaction context,
     *      it will return 0.
     * @param slot The transient storage slot (uint256) to load the value from.
     * @return value The uint256 value loaded from the transient slot.
     */
    function load(uint256 slot) internal view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    /**
     * @notice Stores a boolean value in a transient storage slot.
     * @param slot The transient storage slot.
     * @param value The boolean value to store (true is 1, false is 0).
     */
    function storeBool(uint256 slot, bool value) internal {
        store(slot, value ? 1 : 0);
    }

    /**
     * @notice Loads a boolean value from a transient storage slot.
     * @param slot The transient storage slot.
     * @return The boolean value (true if loaded value is non-zero).
     */
    function loadBool(uint256 slot) internal view returns (bool) {
        return load(slot) != 0;
    }

    /**
     * @notice Stores an address in a transient storage slot.
     * @param slot The transient storage slot.
     * @param value The address value to store.
     */
    function storeAddress(uint256 slot, address value) internal {
        store(slot, uint256(uint160(value)));
    }

    /**
     * @notice Loads an address from a transient storage slot.
     * @param slot The transient storage slot.
     * @return The address value.
     */
    function loadAddress(uint256 slot) internal view returns (address) {
        return address(uint160(load(slot)));
    }

    // Example of how a contract might generate a unique slot for a reentrancy guard
    // This is just an illustrative helper, actual slot management depends on contract needs.
    // bytes32 private constant REENTRANCY_GUARD_SLOT = keccak256("my.app.reentrancy.guard");
    // function getReentrancyGuardSlot() internal pure returns (uint256) {
    //     return uint256(REENTRANCY_GUARD_SLOT);
    // }
}
