// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PackedMerkleLib} from "../src/libraries/PackedMerkleLib.sol";

contract DebtSubsidizerPackedTest is Test {
    using PackedMerkleLib for PackedMerkleLib.PackedMerkleVaultData;

    bytes32 public constant MERKLE_ROOT = keccak256("test_merkle_root");
    uint256 public constant TOTAL_SUBSIDIES = 10000e6;

    mapping(address => PackedMerkleLib.PackedMerkleVaultData) internal _testPackedVaultData;

    function setUp() public {
        address testVault = address(0x1234);
        _testPackedVaultData[testVault].updateRemaining(TOTAL_SUBSIDIES);
    }

    function testUpdateMerkleRootWithPackedStruct() public {
        address testVault = address(0x5678);
        uint256 subsidyAmount = 5000e6;

        _testPackedVaultData[testVault].updateRemaining(subsidyAmount);

        assertEq(_testPackedVaultData[testVault].getRemainingAmount(), subsidyAmount);
        assertEq(_testPackedVaultData[testVault].getClaimedAmount(), 0);
        assertEq(
            _testPackedVaultData[testVault].getRemainingAmount() + _testPackedVaultData[testVault].getClaimedAmount(),
            subsidyAmount
        );

        uint256 additionalSubsidies = 2000e6;
        uint256 currentRemaining = _testPackedVaultData[testVault].getRemainingAmount();
        _testPackedVaultData[testVault].updateRemaining(currentRemaining + additionalSubsidies);

        assertEq(_testPackedVaultData[testVault].getRemainingAmount(), subsidyAmount + additionalSubsidies);
    }

    function testSubsidyClaimWithPackedStruct() public {
        address testVault = address(0x1234);
        uint256 claimAmount = 1000e6;

        _testPackedVaultData[testVault].addToClaimed(claimAmount);
        _testPackedVaultData[testVault].subtractFromRemaining(claimAmount);

        assertEq(_testPackedVaultData[testVault].getRemainingAmount(), TOTAL_SUBSIDIES - claimAmount);
        assertEq(_testPackedVaultData[testVault].getClaimedAmount(), claimAmount);
        assertEq(
            _testPackedVaultData[testVault].getRemainingAmount() + _testPackedVaultData[testVault].getClaimedAmount(),
            TOTAL_SUBSIDIES
        );
    }

    function testPackedStructLimits() public {
        address testVault = address(0x9999);

        // Test maximum values that can be stored in packed struct
        uint256 maxAmount = type(uint96).max;

        _testPackedVaultData[testVault].updateRemaining(maxAmount);

        assertEq(_testPackedVaultData[testVault].getRemainingAmount(), maxAmount);
    }

    function testMultipleVaultsWithPackedStruct() public {
        address vault1 = address(0x1111);
        address vault2 = address(0x2222);
        address vault3 = address(0x3333);

        uint256 amount1 = 1000e6;
        uint256 amount2 = 2000e6;
        uint256 amount3 = 3000e6;

        _testPackedVaultData[vault1].updateRemaining(amount1);
        _testPackedVaultData[vault2].updateRemaining(amount2);
        _testPackedVaultData[vault3].updateRemaining(amount3);

        assertEq(_testPackedVaultData[vault1].getRemainingAmount(), amount1);
        assertEq(_testPackedVaultData[vault2].getRemainingAmount(), amount2);
        assertEq(_testPackedVaultData[vault3].getRemainingAmount(), amount3);

        // Verify independence of vaults
        assertEq(_testPackedVaultData[vault1].getClaimedAmount(), 0);
        assertEq(_testPackedVaultData[vault2].getClaimedAmount(), 0);
        assertEq(_testPackedVaultData[vault3].getClaimedAmount(), 0);
    }

    function testPackedStructIntegrity() public {
        address testVault = address(0x1234);

        // Test that the packed struct maintains data integrity across multiple operations
        uint256 initialAmount = 5000e6;
        uint256 additionalAmount = 3000e6;

        uint256 currentRemaining = _testPackedVaultData[testVault].getRemainingAmount();
        _testPackedVaultData[testVault].updateRemaining(currentRemaining + initialAmount);

        uint256 totalAfterFirst = _testPackedVaultData[testVault].getRemainingAmount();
        assertEq(totalAfterFirst, TOTAL_SUBSIDIES + initialAmount);

        currentRemaining = _testPackedVaultData[testVault].getRemainingAmount();
        _testPackedVaultData[testVault].updateRemaining(currentRemaining + additionalAmount);

        uint256 totalAfterSecond = _testPackedVaultData[testVault].getRemainingAmount();
        assertEq(totalAfterSecond, TOTAL_SUBSIDIES + initialAmount + additionalAmount);

        assertEq(_testPackedVaultData[testVault].getClaimedAmount(), 0);
    }
}
