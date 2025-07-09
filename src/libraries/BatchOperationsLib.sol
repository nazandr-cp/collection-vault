// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILendingManager} from "../interfaces/ILendingManager.sol";
import {IEpochManager} from "../interfaces/IEpochManager.sol";

library BatchOperationsLib {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_BATCH_SIZE = 100;

    error ArrayLengthMismatch();
    error BatchSizeExceeded();
    error ZeroAmount();
    error RepaymentFailed();

    /**
     * @notice Processes batch repayment of borrows with epoch management
     * @param amounts Array of amounts to repay for each borrower
     * @param borrowers Array of borrower addresses
     * @param totalAmount Total amount being repaid
     * @param asset The underlying asset token
     * @param lendingManager The lending manager contract
     * @param epochManager The epoch manager contract (can be address(0))
     * @param epochYieldAllocations Mapping of epoch allocations
     * @param totalYieldReserved Current total yield reserved
     * @return actualTotalRepaid The actual amount repaid
     * @return newTotalYieldReserved The updated total yield reserved
     */
    function processBatchRepayment(
        uint256[] calldata amounts,
        address[] calldata borrowers,
        uint256 totalAmount,
        IERC20 asset,
        ILendingManager lendingManager,
        IEpochManager epochManager,
        mapping(uint256 => uint256) storage epochYieldAllocations,
        uint256 totalYieldReserved
    ) external returns (uint256 actualTotalRepaid, uint256 newTotalYieldReserved) {
        uint256 numEntries = borrowers.length;
        if (numEntries != amounts.length) {
            revert ArrayLengthMismatch();
        }
        if (numEntries > MAX_BATCH_SIZE) {
            revert BatchSizeExceeded();
        }
        if (totalAmount == 0) {
            revert ZeroAmount();
        }

        asset.forceApprove(address(lendingManager), totalAmount);

        for (uint256 i = 0; i < numEntries;) {
            uint256 amt = amounts[i];
            address borrowerAddr = borrowers[i];

            if (amt != 0) {
                try lendingManager.repayBorrowBehalf(borrowerAddr, amt) returns (uint256 lmError) {
                    if (lmError != 0) {
                        revert RepaymentFailed();
                    }
                    actualTotalRepaid += amt;
                } catch {
                    revert RepaymentFailed();
                }
            }
            unchecked {
                ++i;
            }
        }

        asset.forceApprove(address(lendingManager), 0);

        // Update epoch allocations if epoch manager exists
        if (address(epochManager) != address(0)) {
            uint256 epochId = epochManager.getCurrentEpochId();
            if (epochId != 0 && epochYieldAllocations[epochId] >= actualTotalRepaid) {
                epochYieldAllocations[epochId] -= actualTotalRepaid;
            }
        }

        // Update total yield reserved
        if (totalYieldReserved >= actualTotalRepaid) {
            newTotalYieldReserved = totalYieldReserved - actualTotalRepaid;
        } else {
            newTotalYieldReserved = 0;
        }
    }
}
