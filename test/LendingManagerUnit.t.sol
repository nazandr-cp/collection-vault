// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {SimpleMockCToken} from "../src/mocks/SimpleMockCToken.sol";
import {LendingManager} from "../src/LendingManager.sol";
import {ILendingManager} from "../src/interfaces/ILendingManager.sol";
import {ComptrollerInterface, InterestRateModel} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract LendingManagerUnitTest is Test {
    MockERC20 internal asset;
    SimpleMockCToken internal cToken;
    LendingManager internal lm;

    address internal constant OWNER = address(0x1);
    address internal constant VAULT = address(0x2);
    uint256 internal constant INITIAL_EXCHANGE_RATE = 2e28;

    function setUp() public {
        asset = new MockERC20("Mock Token", "MOCK", 18, 0);
        cToken = new SimpleMockCToken(
            address(asset),
            ComptrollerInterface(payable(address(this))),
            InterestRateModel(payable(address(this))),
            INITIAL_EXCHANGE_RATE,
            "Mock cToken",
            "mcTOKEN",
            18,
            payable(OWNER)
        );
        lm = new LendingManager(OWNER, VAULT, address(asset), address(cToken));
    }

    function _mintToVault(uint256 amount) internal {
        asset.mint(VAULT, amount);
        vm.prank(VAULT);
        asset.approve(address(lm), amount);
    }

    function testDepositAndWithdraw() public {
        _mintToVault(100 ether);
        vm.prank(VAULT);
        lm.depositToLendingProtocol(100 ether);
        assertEq(lm.totalPrincipalDeposited(), 100 ether);
        assertEq(cToken.balanceOf(address(lm)), 100 ether);

        vm.prank(VAULT);
        lm.withdrawFromLendingProtocol(40 ether);
        assertEq(lm.totalPrincipalDeposited(), 60 ether);
        assertEq(asset.balanceOf(VAULT), 40 ether);
    }

    function testWithdrawExceedsBalanceReverts() public {
        vm.prank(VAULT);
        vm.expectRevert(ILendingManager.InsufficientBalanceInProtocol.selector);
        lm.withdrawFromLendingProtocol(1 ether);
    }

    function testFuzzDepositWithdraw(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1000 ether));
        _mintToVault(amount);
        vm.prank(VAULT);
        lm.depositToLendingProtocol(amount);
        vm.prank(VAULT);
        lm.withdrawFromLendingProtocol(amount);
        assertEq(asset.balanceOf(VAULT), amount);
        assertEq(lm.totalPrincipalDeposited(), 0);
    }

    function testDepositZeroNoChange() public {
        vm.prank(VAULT);
        bool success = lm.depositToLendingProtocol(0);
        assertTrue(success);
        assertEq(lm.totalPrincipalDeposited(), 0);
    }

    function testWithdrawZeroNoChange() public {
        _mintToVault(10 ether);
        vm.prank(VAULT);
        lm.depositToLendingProtocol(10 ether);
        vm.prank(VAULT);
        bool success = lm.withdrawFromLendingProtocol(0);
        assertTrue(success);
        assertEq(lm.totalPrincipalDeposited(), 10 ether);
    }

    function testWithdrawWhilePaused() public {
        _mintToVault(5 ether);
        vm.prank(VAULT);
        lm.depositToLendingProtocol(5 ether);
        vm.prank(OWNER);
        lm.pause();
        vm.prank(VAULT);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        lm.withdrawFromLendingProtocol(1 ether);
    }

    function testWithdrawBeyondPrincipalWithYield() public {
        _mintToVault(100 ether);
        vm.prank(VAULT);
        lm.depositToLendingProtocol(100 ether);
        asset.mint(address(cToken), 20 ether);
        vm.prank(VAULT);
        lm.withdrawFromLendingProtocol(100 ether);
        assertEq(asset.balanceOf(VAULT), 100 ether);
        assertEq(lm.totalPrincipalDeposited(), 0);
    }
}
