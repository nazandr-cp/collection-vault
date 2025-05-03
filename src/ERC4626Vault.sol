// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ILendingManager} from "./interfaces/ILendingManager.sol";

contract ERC4626Vault is ERC4626, AccessControl {
    using SafeERC20 for IERC20;
    using Math for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    ILendingManager public immutable lendingManager;
    mapping(address => uint256) public collectionTotalAssetsDeposited;
    event CollectionDeposit(address indexed collectionAddress, address indexed caller, address indexed receiver, uint256 assets, uint256 shares);
    event CollectionWithdraw(address indexed collectionAddress, address caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares);
    error LendingManagerDepositFailed();
    error LendingManagerWithdrawFailed();
    error LendingManagerMismatch();
    error AddressZero();
    error Vault_InsufficientBalancePostLMWithdraw();
    error CollectionInsufficientBalance(address collectionAddress, uint256 requested, uint256 available);
    error FunctionDisabled();

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address initialAdmin,
        address _lendingManagerAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        if (_lendingManagerAddress == address(0)) revert AddressZero();
        if (address(_asset) == address(0)) revert AddressZero();
        if (initialAdmin == address(0)) revert AddressZero();
        lendingManager = ILendingManager(_lendingManagerAddress);
        if (address(lendingManager.asset()) != address(_asset)) revert LendingManagerMismatch();
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        IERC20(asset()).approve(_lendingManagerAddress, type(uint256).max);
    }

    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + lendingManager.totalAssets();
    }

    function deposit(uint256, address) public virtual override returns (uint256) {
        revert FunctionDisabled();
    }

    function depositForCollection(uint256 assets, address receiver, address collectionAddress) public virtual returns (uint256 shares) {
        shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, msg.sender, receiver, assets, shares);
    }

    function mint(uint256, address) public virtual override returns (uint256) {
        revert FunctionDisabled();
    }

    function mintForCollection(uint256 shares, address receiver, address collectionAddress) public virtual returns (uint256 assets) {
        assets = previewMint(shares);
        _deposit(msg.sender, receiver, assets, shares);
        _hookDeposit(assets);
        collectionTotalAssetsDeposited[collectionAddress] += assets;
        emit CollectionDeposit(collectionAddress, msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256, address, address) public virtual override returns (uint256) {
        revert FunctionDisabled();
    }

    function withdrawForCollection(uint256 assets, address receiver, address owner, address collectionAddress) public virtual returns (uint256 shares) {
        uint256 collectionBalance = collectionTotalAssetsDeposited[collectionAddress];
        if (assets > collectionBalance) revert CollectionInsufficientBalance(collectionAddress, assets, collectionBalance);
        shares = previewWithdraw(assets);
        _hookWithdraw(assets);
        _withdraw(msg.sender, receiver, owner, assets, shares);
        collectionTotalAssetsDeposited[collectionAddress] = collectionBalance - assets;
        emit CollectionWithdraw(collectionAddress, msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256, address, address) public virtual override returns (uint256) {
        revert FunctionDisabled();
    }

    function redeemForCollection(uint256 shares, address receiver, address owner, address collectionAddress) public virtual returns (uint256 assets) {
        uint256 _totalSupply = totalSupply();
        assets = previewRedeem(shares);
        if (assets == 0) require(shares == 0, "ERC4626: redeem rounds down to zero assets");
        uint256 collectionBalance = collectionTotalAssetsDeposited[collectionAddress];
        _hookWithdraw(assets);
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, shares);
        _burn(owner, shares);
        emit Transfer(owner, address(0), shares);
        uint256 finalAssetsToTransfer = assets;
        bool isFullRedeem = (shares == _totalSupply && shares != 0);
        if (isFullRedeem) {
            uint256 remainingDustInLM = lendingManager.totalAssets();
            if (remainingDustInLM > 0) {
                uint256 redeemedDust = lendingManager.redeemAllCTokens(address(this));
                finalAssetsToTransfer += redeemedDust;
            }
        }
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        if (vaultBalance < finalAssetsToTransfer) revert Vault_InsufficientBalancePostLMWithdraw();
        SafeERC20.safeTransfer(IERC20(asset()), receiver, finalAssetsToTransfer);
        emit Withdraw(msg.sender, receiver, owner, finalAssetsToTransfer, shares);
        collectionTotalAssetsDeposited[collectionAddress] = collectionBalance - assets;
        emit CollectionWithdraw(collectionAddress, msg.sender, receiver, owner, assets, shares);
        return finalAssetsToTransfer;
    }

    function _hookDeposit(uint256 assets) internal virtual {
        if (assets > 0) {
            bool success = lendingManager.depositToLendingProtocol(assets);
            if (!success) revert LendingManagerDepositFailed();
        }
    }

    function _hookWithdraw(uint256 assets) internal virtual {
        if (assets == 0) return;
        IERC20 assetToken = IERC20(asset());
        uint256 directBalance = assetToken.balanceOf(address(this));
        if (directBalance < assets) {
            uint256 neededFromLM = assets - directBalance;
            uint256 availableInLM = lendingManager.totalAssets();
            if (neededFromLM <= availableInLM) {
                if (neededFromLM > 0) {
                    bool success = lendingManager.withdrawFromLendingProtocol(neededFromLM);
                    if (!success) revert LendingManagerWithdrawFailed();
                    uint256 balanceAfterLMWithdraw = assetToken.balanceOf(address(this));
                    if (balanceAfterLMWithdraw < assets) revert Vault_InsufficientBalancePostLMWithdraw();
                }
            }
        }
    }
}
