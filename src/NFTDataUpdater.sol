// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin-contracts-5.2.0/access/Ownable.sol";
import {INFTDataUpdater} from "./interfaces/INFTDataUpdater.sol";
import {IRewardsController} from "./interfaces/IRewardsController.sol";

contract NFTDataUpdater is INFTDataUpdater, Ownable {
    IRewardsController public rewardsController;
    mapping(address => bool) public authorizedUpdaters;

    event RewardsControllerSet(address indexed controller);
    event UpdaterAuthorizationSet(address indexed updater, bool authorized);

    error AddressZero();
    error CallerNotAuthorized();
    error ControllerNotSet();

    constructor(address initialOwner, address _rewardsControllerAddress) Ownable(initialOwner) {
        if (_rewardsControllerAddress == address(0)) revert AddressZero();
        rewardsController = IRewardsController(_rewardsControllerAddress);
        authorizedUpdaters[initialOwner] = true;
        emit RewardsControllerSet(_rewardsControllerAddress);
        emit UpdaterAuthorizationSet(initialOwner, true);
    }

    function setRewardsController(address _rewardsControllerAddress) external onlyOwner {
        if (_rewardsControllerAddress == address(0)) revert AddressZero();
        rewardsController = IRewardsController(_rewardsControllerAddress);
        emit RewardsControllerSet(_rewardsControllerAddress);
    }

    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorizationSet(updater, authorized);
    }

    function updateNFTBalance(address user, address nftCollection, uint256 currentBalance) external override {
        if (!authorizedUpdaters[msg.sender]) revert CallerNotAuthorized();
        if (address(rewardsController) == address(0)) revert ControllerNotSet();

        rewardsController.updateNFTBalance(user, nftCollection, currentBalance);
    }

    function updateNFTBalances(address user, address[] calldata nftCollections, uint256[] calldata currentBalances)
        external
        override
    {
        if (!authorizedUpdaters[msg.sender]) revert CallerNotAuthorized();
        if (address(rewardsController) == address(0)) revert ControllerNotSet();

        rewardsController.updateNFTBalances(user, nftCollections, currentBalances);
    }
}
