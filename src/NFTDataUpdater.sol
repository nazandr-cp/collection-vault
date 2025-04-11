// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {INFTDataUpdater} from "./interfaces/INFTDataUpdater.sol";
import {IRewardsController} from "./interfaces/IRewardsController.sol";

/**
 * @title NFTDataUpdater
 * @notice A basic implementation for updating NFT balances in the RewardsController.
 * @dev This contract acts as a proxy, forwarding calls from an authorized source (e.g., backend oracle)
 *      to the RewardsController. Access control should be managed carefully (e.g., Ownable, specific oracle address).
 */
contract NFTDataUpdater is INFTDataUpdater, Ownable {
    IRewardsController public rewardsController;
    mapping(address => bool) public authorizedUpdaters; // Addresses allowed to push updates

    // --- Events ---
    event RewardsControllerSet(address indexed controller);
    event UpdaterAuthorizationSet(address indexed updater, bool authorized);

    // --- Errors ---
    error AddressZero();
    error CallerNotAuthorized();
    error ControllerNotSet();

    // --- Constructor ---
    constructor(address initialOwner, address _rewardsControllerAddress) Ownable(initialOwner) {
        if (_rewardsControllerAddress == address(0)) revert AddressZero();
        rewardsController = IRewardsController(_rewardsControllerAddress);
        authorizedUpdaters[initialOwner] = true; // Initially, only owner can update
        emit RewardsControllerSet(_rewardsControllerAddress);
        emit UpdaterAuthorizationSet(initialOwner, true);
    }

    // --- Admin Functions ---

    function setRewardsController(address _rewardsControllerAddress) external onlyOwner {
        if (_rewardsControllerAddress == address(0)) revert AddressZero();
        rewardsController = IRewardsController(_rewardsControllerAddress);
        emit RewardsControllerSet(_rewardsControllerAddress);
    }

    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorizationSet(updater, authorized);
    }

    // --- INFTDataUpdater Implementation ---

    /**
     * @notice Forwards the NFT balance update to the RewardsController.
     * @dev Requires the caller to be authorized.
     */
    function updateNFTBalance(address user, address nftCollection, uint256 currentBalance) external override {
        if (!authorizedUpdaters[msg.sender]) revert CallerNotAuthorized();
        if (address(rewardsController) == address(0)) revert ControllerNotSet();

        // Forward the call
        rewardsController.updateNFTBalance(user, nftCollection, currentBalance);
    }

    /**
     * @notice Forwards the batch NFT balance update to the RewardsController.
     * @dev Requires the caller to be authorized.
     */
    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata currentBalances)
        external
        override
    {
        if (!authorizedUpdaters[msg.sender]) revert CallerNotAuthorized();
        if (address(rewardsController) == address(0)) revert ControllerNotSet();

        // Forward the call
        rewardsController.updateNFTBalances(user, nftCollections, currentBalances);
    }
}
