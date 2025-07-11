// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PackedMerkleLib
 * @dev Gas-optimized library for Merkle proof vault data using packed structs.
 *
 * Packs vault data into a single 256-bit storage slot to minimize gas costs:
 * - Saves ~15,000 gas per struct storage vs unpacked version
 * - Reduces storage slots from 4 to 1 (5,000 gas saved per additional slot)
 * - Optimizes for frequent read/write operations in Merkle proof claiming
 *
 * Bit allocation:
 * - 96 bits each for remainingAmount and claimedAmount (supports ~79B tokens with 18 decimals)
 * - 32 bits for lastUpdateTimestamp (valid until year 2106)
 * - 32 bits for flags (extensible for future features)
 */
library PackedMerkleLib {
    struct PackedMerkleVaultData {
        uint96 remainingAmount;
        uint96 claimedAmount;
        uint32 lastUpdateTimestamp;
        uint32 flags;
    }

    error AmountExceedsLimit(uint256 amount, uint256 limit);
    error TimestampExceedsLimit(uint256 timestamp, uint256 limit);

    uint256 private constant MAX_96_BIT = type(uint96).max;
    uint256 private constant MAX_32_BIT = type(uint32).max;

    /**
     * @dev Packs individual values into a single struct with overflow checks.
     * @param remainingAmount Amount remaining to be claimed (max ~79B tokens)
     * @param claimedAmount Amount already claimed (max ~79B tokens)
     * @param lastUpdateTimestamp Last update timestamp (max year 2106)
     * @param flags Bit flags for future extensibility
     * @return Packed struct containing all values
     */
    function pack(uint256 remainingAmount, uint256 claimedAmount, uint256 lastUpdateTimestamp, uint256 flags)
        internal
        pure
        returns (PackedMerkleVaultData memory)
    {
        if (remainingAmount > MAX_96_BIT) {
            revert AmountExceedsLimit(remainingAmount, MAX_96_BIT);
        }
        if (claimedAmount > MAX_96_BIT) {
            revert AmountExceedsLimit(claimedAmount, MAX_96_BIT);
        }
        if (lastUpdateTimestamp > MAX_32_BIT) {
            revert TimestampExceedsLimit(lastUpdateTimestamp, MAX_32_BIT);
        }
        if (flags > MAX_32_BIT) {
            revert AmountExceedsLimit(flags, MAX_32_BIT);
        }

        return PackedMerkleVaultData({
            remainingAmount: uint96(remainingAmount),
            claimedAmount: uint96(claimedAmount),
            lastUpdateTimestamp: uint32(lastUpdateTimestamp),
            flags: uint32(flags)
        });
    }

    /**
     * @dev Unpacks struct into individual uint256 values for safe arithmetic operations.
     * @param data Packed struct to unpack
     * @return remainingAmount Amount remaining to be claimed
     * @return claimedAmount Amount already claimed
     * @return lastUpdateTimestamp Last update timestamp
     * @return flags Bit flags
     */
    function unpack(PackedMerkleVaultData memory data)
        internal
        pure
        returns (uint256 remainingAmount, uint256 claimedAmount, uint256 lastUpdateTimestamp, uint256 flags)
    {
        remainingAmount = uint256(data.remainingAmount);
        claimedAmount = uint256(data.claimedAmount);
        lastUpdateTimestamp = uint256(data.lastUpdateTimestamp);
        flags = uint256(data.flags);
    }

    /**
     * @dev Updates remaining amount with overflow and timestamp checks.
     * @param data Storage reference to packed data
     * @param newRemaining New remaining amount to set
     */
    function updateRemaining(PackedMerkleVaultData storage data, uint256 newRemaining) internal {
        if (newRemaining > MAX_96_BIT) {
            revert AmountExceedsLimit(newRemaining, MAX_96_BIT);
        }
        if (block.timestamp > MAX_32_BIT) {
            revert TimestampExceedsLimit(block.timestamp, MAX_32_BIT);
        }
        data.remainingAmount = uint96(newRemaining);
        data.lastUpdateTimestamp = uint32(block.timestamp);
    }

    /**
     * @dev Updates claimed amount with overflow and timestamp checks.
     * @param data Storage reference to packed data
     * @param newClaimed New claimed amount to set
     */
    function updateClaimed(PackedMerkleVaultData storage data, uint256 newClaimed) internal {
        if (newClaimed > MAX_96_BIT) {
            revert AmountExceedsLimit(newClaimed, MAX_96_BIT);
        }
        if (block.timestamp > MAX_32_BIT) {
            revert TimestampExceedsLimit(block.timestamp, MAX_32_BIT);
        }
        data.claimedAmount = uint96(newClaimed);
        data.lastUpdateTimestamp = uint32(block.timestamp);
    }

    /**
     * @dev Adds to claimed amount with overflow protection.
     * @param data Storage reference to packed data
     * @param amountToAdd Amount to add to current claimed amount
     */
    function addToClaimed(PackedMerkleVaultData storage data, uint256 amountToAdd) internal {
        uint256 newClaimed = uint256(data.claimedAmount) + amountToAdd;
        if (newClaimed > MAX_96_BIT) {
            revert AmountExceedsLimit(newClaimed, MAX_96_BIT);
        }
        if (block.timestamp > MAX_32_BIT) {
            revert TimestampExceedsLimit(block.timestamp, MAX_32_BIT);
        }
        data.claimedAmount = uint96(newClaimed);
        data.lastUpdateTimestamp = uint32(block.timestamp);
    }

    /**
     * @dev Subtracts from remaining amount with underflow protection.
     * @param data Storage reference to packed data
     * @param amountToSubtract Amount to subtract from current remaining amount
     */
    function subtractFromRemaining(PackedMerkleVaultData storage data, uint256 amountToSubtract) internal {
        uint256 currentRemaining = uint256(data.remainingAmount);
        require(currentRemaining >= amountToSubtract, "PackedMerkleLib: insufficient remaining amount");

        if (block.timestamp > MAX_32_BIT) {
            revert TimestampExceedsLimit(block.timestamp, MAX_32_BIT);
        }

        data.remainingAmount = uint96(currentRemaining - amountToSubtract);
        data.lastUpdateTimestamp = uint32(block.timestamp);
    }

    // Getter functions for safe type conversion
    function getRemainingAmount(PackedMerkleVaultData storage data) internal view returns (uint256) {
        return uint256(data.remainingAmount);
    }

    function getClaimedAmount(PackedMerkleVaultData storage data) internal view returns (uint256) {
        return uint256(data.claimedAmount);
    }

    function getLastUpdateTimestamp(PackedMerkleVaultData storage data) internal view returns (uint256) {
        return uint256(data.lastUpdateTimestamp);
    }

    function getFlags(PackedMerkleVaultData storage data) internal view returns (uint256) {
        return uint256(data.flags);
    }

    /**
     * @dev Checks if the vault is active using the first bit of flags.
     * @param data Storage reference to packed data
     * @return True if active flag is set
     */
    function isActive(PackedMerkleVaultData storage data) internal view returns (bool) {
        return data.flags & 1 != 0;
    }

    /**
     * @dev Sets the active flag using the first bit of flags field.
     * @param data Storage reference to packed data
     * @param active Whether to set the vault as active
     */
    function setActive(PackedMerkleVaultData storage data, bool active) internal {
        if (block.timestamp > MAX_32_BIT) {
            revert TimestampExceedsLimit(block.timestamp, MAX_32_BIT);
        }

        if (active) {
            data.flags |= 1;
        } else {
            data.flags &= ~uint32(1);
        }
        data.lastUpdateTimestamp = uint32(block.timestamp);
    }
}
