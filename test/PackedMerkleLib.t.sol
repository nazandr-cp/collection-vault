// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PackedMerkleLib} from "../src/libraries/PackedMerkleLib.sol";

contract PackedMerkleLibTest is Test {
    using PackedMerkleLib for PackedMerkleLib.PackedMerkleVaultData;

    PackedMerkleLib.PackedMerkleVaultData testData;

    function setUp() public {
        testData = PackedMerkleLib.PackedMerkleVaultData({
            remainingAmount: 0,
            claimedAmount: 0,
            lastUpdateTimestamp: 0,
            flags: 0
        });
    }

    function testPack() public {
        uint256 remaining = 1000e18;
        uint256 claimed = 500e18;
        uint256 timestamp = block.timestamp;
        uint256 flags = 1;

        PackedMerkleLib.PackedMerkleVaultData memory packed = PackedMerkleLib.pack(remaining, claimed, timestamp, flags);

        assertEq(packed.remainingAmount, remaining);
        assertEq(packed.claimedAmount, claimed);
        assertEq(packed.lastUpdateTimestamp, timestamp);
        assertEq(packed.flags, flags);
    }

    function testUnpack() public {
        uint256 remaining = 1000e18;
        uint256 claimed = 500e18;
        uint256 timestamp = block.timestamp;
        uint256 flags = 1;

        PackedMerkleLib.PackedMerkleVaultData memory packed = PackedMerkleLib.pack(remaining, claimed, timestamp, flags);

        (uint256 unpackedRemaining, uint256 unpackedClaimed, uint256 unpackedTimestamp, uint256 unpackedFlags) =
            PackedMerkleLib.unpack(packed);

        assertEq(unpackedRemaining, remaining);
        assertEq(unpackedClaimed, claimed);
        assertEq(unpackedTimestamp, timestamp);
        assertEq(unpackedFlags, flags);
    }

    function testUpdateRemaining() public {
        uint256 newRemaining = 2000e18;

        testData.updateRemaining(newRemaining);

        assertEq(testData.getRemainingAmount(), newRemaining);
        assertEq(testData.getLastUpdateTimestamp(), block.timestamp);
    }

    function testUpdateClaimed() public {
        uint256 newClaimed = 750e18;

        testData.updateClaimed(newClaimed);

        assertEq(testData.getClaimedAmount(), newClaimed);
        assertEq(testData.getLastUpdateTimestamp(), block.timestamp);
    }

    function testAddToClaimed() public {
        uint256 initialClaimed = 500e18;
        uint256 amountToAdd = 250e18;

        testData.updateClaimed(initialClaimed);
        testData.addToClaimed(amountToAdd);

        assertEq(testData.getClaimedAmount(), initialClaimed + amountToAdd);
    }

    function testSubtractFromRemaining() public {
        uint256 initialRemaining = 1000e18;
        uint256 amountToSubtract = 300e18;

        testData.updateRemaining(initialRemaining);
        testData.subtractFromRemaining(amountToSubtract);

        assertEq(testData.getRemainingAmount(), initialRemaining - amountToSubtract);
    }

    function testIsActiveFlags() public {
        assertFalse(testData.isActive());

        testData.setActive(true);
        assertTrue(testData.isActive());

        testData.setActive(false);
        assertFalse(testData.isActive());
    }

    function testPackAmountAtLimit() public {
        uint256 maxAmount = type(uint96).max;
        uint256 maxTimestamp = type(uint32).max;

        PackedMerkleLib.PackedMerkleVaultData memory packed =
            PackedMerkleLib.pack(maxAmount, maxAmount, maxTimestamp, 0);

        assertEq(packed.remainingAmount, maxAmount);
        assertEq(packed.claimedAmount, maxAmount);
        assertEq(packed.lastUpdateTimestamp, maxTimestamp);
    }

    function testAddToClaimedAtLimit() public {
        uint256 nearLimit = type(uint96).max - 1000;
        uint256 amountToAdd = 500;

        testData.updateClaimed(nearLimit);
        testData.addToClaimed(amountToAdd);

        assertEq(testData.getClaimedAmount(), nearLimit + amountToAdd);
    }

    function testSubtractFromRemainingValid() public {
        uint256 initialRemaining = 1000e18;
        uint256 amountToSubtract = 300e18;

        testData.updateRemaining(initialRemaining);
        testData.subtractFromRemaining(amountToSubtract);

        assertEq(testData.getRemainingAmount(), initialRemaining - amountToSubtract);
    }

    function testMaxValues() public {
        uint256 maxAmount = type(uint96).max;
        uint256 maxTimestamp = type(uint32).max;
        uint256 maxFlags = type(uint32).max;

        PackedMerkleLib.PackedMerkleVaultData memory packed =
            PackedMerkleLib.pack(maxAmount, maxAmount, maxTimestamp, maxFlags);

        assertEq(packed.remainingAmount, maxAmount);
        assertEq(packed.claimedAmount, maxAmount);
        assertEq(packed.lastUpdateTimestamp, maxTimestamp);
        assertEq(packed.flags, maxFlags);
    }

    function testGetters() public {
        uint256 remaining = 1000e18;
        uint256 claimed = 500e18;
        uint256 timestamp = block.timestamp;
        uint256 flags = 15;

        testData.updateRemaining(remaining);
        testData.updateClaimed(claimed);
        testData.flags = uint32(flags);

        assertEq(testData.getRemainingAmount(), remaining);
        assertEq(testData.getClaimedAmount(), claimed);
        assertEq(testData.getLastUpdateTimestamp(), timestamp);
        assertEq(testData.getFlags(), flags);
    }
}
