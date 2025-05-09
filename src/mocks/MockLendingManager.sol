// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CTokenInterface, CErc20Interface} from "compound-protocol-2.8.1/contracts/CTokenInterfaces.sol";
import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {MockCToken} from "./MockCToken.sol";
// import {console} from "forge-std/console.sol"; // Import console

/**
 * @title MockLendingManager
 * @notice Mock contract for testing ERC4626Vault interactions.
 */
contract MockLendingManager is ILendingManager {
    // --- State Variables from LendingManager ---
    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 public constant REWARDS_CONTROLLER_ROLE = keccak256("REWARDS_CONTROLLER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE"); // DEFAULT_ADMIN_ROLE is part of AccessControl

    uint256 public constant R0_BASIS_POINTS = 5;
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;
    // PRECISION and EXCHANGE_RATE_DENOMINATOR are private constants, not part of public interface

    IERC20 public asset; // Matches asset() getter
    CTokenInterface private _cToken; // Internal in LendingManager, private here is fine for mock
    uint256 public totalPrincipalDeposited;

    // --- Mock Specific State Variables ---
    mapping(address => uint256) public principalDepositedByVault; // Renamed for clarity
    uint256 private _mockAvailableYield = type(uint256).max;
    address public rewardsControllerAddressMock; // To avoid conflict if inheriting AccessControl roles
    address public mockCTokenAddress;
    uint256 internal mockBaseRewardPerBlock;
    uint256 internal mockTotalAssets;
    bool internal shouldTransferYieldRevert;
    bool public depositResult = true;
    bool public withdrawResult = true;
    bool public transferYieldResult = true;
    uint256 public depositCalledCount;
    uint256 public withdrawCalledCount;
    uint256 public transferYieldCalledCount;
    address public expectedTransferRecipient;
    bool private recipientExpectationSet = false;
    bool public transferYieldBatchResult = true;
    uint256 public transferYieldBatchCalledCount;

    // --- Events from LendingManager ---
    event YieldTransferred(address indexed recipient, uint256 amount);
    event YieldTransferredBatch(
        address indexed recipient, uint256 totalAmount, address[] collections, uint256[] amounts
    );
    event DepositToProtocol(address indexed caller, uint256 amount);
    event WithdrawFromProtocol(address indexed caller, uint256 amount);

    // --- Errors from LendingManager ---
    error MintFailed();
    error RedeemFailed();
    error TransferYieldFailed(); // Though SafeERC20 might make it redundant
    error AddressZero();
    error InsufficientBalanceInProtocol();
    error LM_CallerNotVault(address caller);
    error LM_CallerNotRewardsController(address caller);
    error CannotRemoveLastAdmin(bytes32 role);
    error ArrayLengthMismatch(); // Added from transferYieldBatch in original

    // --- Mock Specific Events ---
    event MockDepositCalled(uint256 amount);
    event MockWithdrawCalled(uint256 amount);
    event MockTransferYieldCalled(uint256 amount, address recipient);
    event MockTransferYieldBatchCalled(
        address[] collections, uint256[] amounts, uint256 totalAmount, address recipient, uint256 totalAmountTransferred
    );

    constructor(IERC20 _asset, CTokenInterface __cToken) {
        asset = _asset;
        _cToken = __cToken;
    }

    // --- ILendingManager Interface Functions ---
    // asset() is implicitly provided by public state variable `asset`

    function cToken() external view override returns (address) {
        return address(_cToken);
    }

    // --- Mock Control Functions ---
    function setRewardsController(address _controller) external {
        rewardsControllerAddressMock = _controller;
    }

    function setMockCTokenAddress(address _cToken) external {
        mockCTokenAddress = _cToken;
    }

    function setDepositResult(bool _result) external {
        depositResult = _result;
    }

    function setWithdrawResult(bool _result) external {
        withdrawResult = _result;
    }

    function setMockBaseRewardPerBlock(uint256 _reward) external {
        mockBaseRewardPerBlock = _reward;
    }

    function setMockTotalAssets(uint256 _assets) external {
        mockTotalAssets = _assets;
    }

    function setShouldTransferYieldRevert(bool _revert) external {
        shouldTransferYieldRevert = _revert;
    }

    function setMockAvailableYield(uint256 _yield) external {
        _mockAvailableYield = _yield;
    }

    function setExpectedRecipient(address _recipient) external {
        expectedTransferRecipient = _recipient;
        recipientExpectationSet = true;
    }

    // --- ILendingManager Implementation ---
    function depositToLendingProtocol(uint256 amount) external override returns (bool success) {
        depositCalledCount++;
        emit MockDepositCalled(amount); // Mock specific event

        if (!depositResult) {
            // revert MintFailed(); // Or return false as per current mock logic
            return false;
        }
        if (amount == 0) {
            return true;
        }

        // Simulate LM pulling assets from the Vault (msg.sender)
        // Requires Vault to have approved the LM
        // In a real scenario, this would be asset.safeTransferFrom
        asset.transferFrom(msg.sender, address(this), amount);
        totalPrincipalDeposited += amount; // Mirroring LendingManager logic
        principalDepositedByVault[msg.sender] += amount;

        emit DepositToProtocol(msg.sender, amount); // LendingManager event
        return true;
    }

    function withdrawFromLendingProtocol(uint256 amount) external override returns (bool success) {
        withdrawCalledCount++;
        emit MockWithdrawCalled(amount); // Mock specific event

        if (!withdrawResult) {
            // revert RedeemFailed(); // Or return false
            return false;
        }
        if (amount == 0) {
            return true;
        }

        uint256 availableBalance = this.totalAssets(); // Use the mock's totalAssets
        if (availableBalance < amount) {
            // revert InsufficientBalanceInProtocol();
            return false; // Or revert as per actual contract
        }

        // Simulate asset transfer FROM mock TO vault
        // In a real scenario, this would be asset.safeTransfer
        asset.transfer(msg.sender, amount);

        if (totalPrincipalDeposited >= amount) {
            totalPrincipalDeposited -= amount;
        } else {
            totalPrincipalDeposited = 0;
        }
        if (principalDepositedByVault[msg.sender] >= amount) {
            principalDepositedByVault[msg.sender] -= amount;
        } else {
            principalDepositedByVault[msg.sender] = 0;
        }

        emit WithdrawFromProtocol(msg.sender, amount); // LendingManager event
        return true;
    }

    function totalAssets() public view override returns (uint256) {
        // Changed to public to match LM
        // Return mock value if set, otherwise fallback (e.g., balance)
        return mockTotalAssets > 0 ? mockTotalAssets : asset.balanceOf(address(this));
    }

    function getBaseRewardPerBlock() external view override returns (uint256) {
        // Return mock value
        return mockBaseRewardPerBlock;
    }

    function getAvailableYield() external view returns (uint256) {
        // Removed override
        return _mockAvailableYield;
    }

    function transferYield(uint256 amount, address recipient) external override returns (uint256 amountTransferred) {
        transferYieldCalledCount++;
        emit MockTransferYieldCalled(amount, recipient); // Mock specific event

        // Basic checks from LendingManager
        if (recipient == address(0)) {
            revert AddressZero();
        }
        // Mock doesn't have roles, so can't check onlyRewardsController directly
        // require(msg.sender == rewardsControllerAddressMock, "MockLM: Caller is not the RewardsController");

        if (recipientExpectationSet) {
            require(recipient == expectedTransferRecipient, "MockLM: Transfer recipient mismatch");
            recipientExpectationSet = false;
        }

        if (shouldTransferYieldRevert) {
            revert("MockLM: transferYield forced revert"); // Or revert TransferYieldFailed();
        }

        if (amount == 0) return 0;

        uint256 availableYield = this.getAvailableYield();
        amountTransferred = amount > availableYield ? availableYield : amount;

        if (amountTransferred > 0 && transferYieldResult) {
            // Simulate transfer
            asset.transfer(recipient, amountTransferred);
            emit YieldTransferred(recipient, amountTransferred); // LendingManager event
        } else {
            amountTransferred = 0; // Simulate failure or no yield
        }
        return amountTransferred;
    }

    function transferYieldBatch(
        address[] calldata collections,
        uint256[] calldata amounts,
        uint256 totalAmount,
        address recipient
    ) external override returns (uint256 totalAmountTransferred) {
        transferYieldBatchCalledCount++;
        emit MockTransferYieldBatchCalled(collections, amounts, totalAmount, recipient, 0); // Mock event, amount later

        if (recipient == address(0)) {
            revert AddressZero();
        }
        if (collections.length != amounts.length) {
            revert ArrayLengthMismatch();
        }
        // Mock doesn't have roles, so can't check onlyRewardsController directly
        // require(msg.sender == rewardsControllerAddressMock, "MockLM: Caller is not RC for batch");

        if (recipientExpectationSet) {
            require(recipient == expectedTransferRecipient, "MockLM: Batch recipient mismatch");
        }

        if (shouldTransferYieldRevert) {
            revert("MockLM: transferYieldBatch forced revert"); // Or revert TransferYieldFailed();
        }

        if (totalAmount == 0) return 0;

        uint256 availableYield = this.getAvailableYield();
        totalAmountTransferred = totalAmount > availableYield ? availableYield : totalAmount;

        if (totalAmountTransferred > 0 && transferYieldBatchResult) {
            asset.transfer(recipient, totalAmountTransferred);
            // For the event, we pass the original collections and amounts, but the actual total transferred
            emit YieldTransferredBatch(recipient, totalAmountTransferred, collections, amounts); // LendingManager event
        } else {
            totalAmountTransferred = 0;
        }
        // Update the mock event emission if needed, or remove if redundant with LM event
        // For now, the initial emit MockTransferYieldBatchCalled is kept, could refine
        return totalAmountTransferred;
    }

    function redeemAllCTokens(address recipient) external override returns (uint256 amountRedeemed) {
        if (recipient == address(0)) {
            revert AddressZero();
        }
        // Mock logic: redeem all available assets or a mock amount
        amountRedeemed = asset.balanceOf(address(this)); // Simplistic: redeem all current asset balance
        if (mockTotalAssets > 0 && mockTotalAssets < amountRedeemed) {
            // If mockTotalAssets is set, use it
            amountRedeemed = mockTotalAssets;
        }

        if (amountRedeemed > 0) {
            asset.transfer(recipient, amountRedeemed);
            emit WithdrawFromProtocol(recipient, amountRedeemed); // LendingManager event
        }
        return amountRedeemed;
    }

    // --- Role Management Functions (Stubs) ---
    // These functions are part of LendingManager's interface due to AccessControl.
    // In the mock, they are stubs as AccessControl is not inherited.
    // They don't have `onlyRole` modifiers here.

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function grantRewardsControllerRole(address newController) external {
        if (newController == address(0)) revert AddressZero();
        // Mock implementation: can emit an event or do nothing
        emit RoleGranted(REWARDS_CONTROLLER_ROLE, newController, msg.sender);
    }

    function revokeRewardsControllerRole(address controller) external {
        if (controller == address(0)) revert AddressZero();
        emit RoleRevoked(REWARDS_CONTROLLER_ROLE, controller, msg.sender);
    }

    function grantVaultRole(address newVault) external {
        if (newVault == address(0)) revert AddressZero();
        emit RoleGranted(VAULT_ROLE, newVault, msg.sender);
    }

    function revokeVaultRole(address vault) external {
        if (vault == address(0)) revert AddressZero();
        emit RoleRevoked(VAULT_ROLE, vault, msg.sender);
    }

    function grantAdminRole(address newAdmin) external {
        if (newAdmin == address(0)) revert AddressZero();
        emit RoleGranted(ADMIN_ROLE, newAdmin, msg.sender);
    }

    function revokeAdminRole(address admin) external {
        if (admin == address(0)) revert AddressZero();
        emit RoleRevoked(ADMIN_ROLE, admin, msg.sender);
    }

    // DEFAULT_ADMIN_ROLE is typically managed by AccessControl itself.
    // For a mock, we can add stubs if these specific functions are called.
    // The actual DEFAULT_ADMIN_ROLE constant is not exposed by LendingManager directly,
    // but functions using it are.
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // Standard DEFAULT_ADMIN_ROLE

    function grantAdminRoleAsDefaultAdmin(address newAdmin) external {
        if (newAdmin == address(0)) revert AddressZero();
        // require(msg.sender == getRoleAdmin(DEFAULT_ADMIN_ROLE), "AccessControl: sender must be admin to grant");
        emit RoleGranted(ADMIN_ROLE, newAdmin, msg.sender); // Assuming msg.sender is default admin for mock
    }

    function revokeAdminRoleAsDefaultAdmin(address admin) external {
        if (admin == address(0)) revert AddressZero();
        // require(msg.sender == getRoleAdmin(DEFAULT_ADMIN_ROLE), "AccessControl: sender must be admin to revoke");
        emit RoleRevoked(ADMIN_ROLE, admin, msg.sender); // Assuming msg.sender is default admin for mock
    }

    // --- Helper to check role admin (mocked) ---
    // function getRoleAdmin(bytes32 role) public view returns (bytes32) {
    //     // Simplified mock: All roles managed by DEFAULT_ADMIN_ROLE
    //     return DEFAULT_ADMIN_ROLE;
    // }
}
