// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// TODO: Import FullMath512 once available e.g. import {FullMath512} from "../libraries/FullMath512.sol";
// TODO: Import RateLimiter once available e.g. import {RateLimiter} from "../libraries/RateLimiter.sol";
import {ISubsidyDistributor} from "./interfaces/ISubsidyDistributor.sol";
import {IMarketVault} from "./interfaces/IMarketVault.sol";
// TODO: Import IRootGuardian once available e.g. import {IRootGuardian} from "./interfaces/IRootGuardian.sol";

/**
 * @title SubsidyDistributor
 * @author Your Name/Team
 * @notice Manages yield buffering from MarketVault, calculates Exponential Moving Average (EMA)
 * of yield, and distributes subsidies to users based on a global index.
 * It includes mechanisms for rate limiting index updates and user reward accrual/claims.
 */
contract SubsidyDistributor is ISubsidyDistributor, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --- Structs ---

    /**
     * @dev MarketPacked struct, mirroring the one in MarketVault for EMA calculations.
     * @param index64x64 Global market index, Q64.64 format.
     * @param totalBorrowEMA Exponential Moving Average of total borrows, scaled.
     * @param lastBlock The block number of the last EMA update.
     */
    struct MarketPacked {
        uint128 index64x64; // Matches globalIndex in this contract
        uint120 totalBorrowEMA;
        uint40 lastBlock;
    }

    // --- State Variables ---

    IERC20 public immutable underlyingAsset;
    IMarketVault public marketVault;
    // TODO: IRootGuardian public rootGuardian;

    mapping(address => User) private _users;

    uint256 public currentBufferAmount;
    uint256 public yieldSinceLastPush;
    uint256 private _lastPushTimestamp;

    uint128 public override globalIndex; // Q64.64 format, corresponds to MarketPacked.index64x64
    uint120 private _totalBorrowEMA;
    uint40 private _lastBlock;

    // Rate Limiting Parameters
    uint256 public override deltaIdxMax; // Maximum allowed change in globalIndex per pushIndex call
    uint256 public emaMin; // Minimum bound for EMA
    uint256 public emaMax; // Maximum bound for EMA

    // --- Constants ---
    // TODO: Define appropriate constants, e.g., for EMA calculation if not from RateLimiter
    // uint256 private constant ONE_1E18 = 1e18; // Example for mulDiv512

    // --- Modifiers ---

    modifier onlyMarketVault() {
        if (msg.sender != address(marketVault)) revert OnlyMarketVault();
        _;
    }

    // --- Errors ---
    error OnlyMarketVault();
    error InvalidAmount();
    error AddressZero();
    error IndexUpdateOverflow(uint256 dIdx, uint256 maxAllowed);
    error EmaOutOfBounds(uint120 ema, uint256 min, uint256 max);
    error InsufficientAccruedRewards(address user, uint256 claimed, uint256 accrued);
    error NotImplemented();
    // TODO: Add more custom errors as needed (e.g., for RootGuardian interactions)

    // --- Constructor ---

    /**
     * @notice Initializes the SubsidyDistributor contract.
     * @param _underlyingAsset The address of the underlying ERC20 asset (must match MarketVault's asset).
     * @param _marketVault Address of the MarketVault contract.
     * @param _underlyingAsset The address of the underlying ERC20 asset (must match MarketVault's asset).
     * @param _marketVault Address of the MarketVault contract.
     * @param _initialOwner Address of the initial owner.
     * @param _initialOwner Address of the initial owner.
     * @param _deltaIdxMax Initial value for deltaIdxMax.
     * @param _emaMin Initial value for emaMin.
     * @param _emaMax Initial value for emaMax.
     */
    constructor(
        address _underlyingAsset,
        address _marketVault,
        address, /*_rootGuardian*/ // TODO: Uncomment when IRootGuardian is available
        address _initialOwner,
        uint256 _deltaIdxMax,
        uint256 _emaMin,
        uint256 _emaMax
    ) Ownable(_initialOwner) {
        if (
            _underlyingAsset == address(0) || _marketVault == address(0) /*|| _rootGuardian == address(0)*/
                || _initialOwner == address(0)
        ) {
            revert AddressZero();
        }
        if (_deltaIdxMax == 0 || _emaMin == 0 || _emaMax == 0 || _emaMin >= _emaMax) {
            revert InvalidAmount(); // Or a more specific error
        }

        underlyingAsset = IERC20(_underlyingAsset);
        marketVault = IMarketVault(_marketVault);
        // TODO: rootGuardian = IRootGuardian(_rootGuardian);

        deltaIdxMax = _deltaIdxMax;
        emaMin = _emaMin;
        emaMax = _emaMax;

        // Initialize globalIndex (Q64.64 format, typically starts at 1 << 64)
        globalIndex = 1 << 64;
        _lastBlock = uint40(block.number); // Initialize lastBlock for EMA
    }

    // --- External Functions ---

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function takeBuffer(uint256 amount) external override onlyMarketVault nonReentrant {
        if (amount == 0) revert InvalidAmount();

        currentBufferAmount += amount;
        yieldSinceLastPush += amount;

        // Ensure MarketVault transfers the tokens to this contract
        // This function assumes the transfer has already happened or will happen
        // as part of MarketVault's pullYield() -> takeBuffer() flow.
        // A direct underlyingAsset.safeTransferFrom(address(marketVault), address(this), amount);
        // might be redundant if MarketVault already sent them.
        // For safety, ensure this contract has the tokens.
        // This check is more of an invariant check post-call from MarketVault.
        // If MarketVault is trusted, this can be omitted for gas.
        // require(underlyingAsset.balanceOf(address(this)) >= currentBufferAmount, "Buffer mismatch");

        emit BufferReceived(address(marketVault), amount);
    }

    /**
     * @inheritdoc ISubsidyDistributor
     * @dev Placeholder for EMA calculation. Actual logic depends on RateLimiter and specific EMA formula.
     * This function should update `totalBorrowEMA_` and `lastBlock_`.
     */
    function lazyEMA() external override nonReentrant {
        revert NotImplemented(); // TODO: Implement EMA calculation logic
            // 1. Get current total borrows from MarketVault or relevant source.
            // 2. Calculate time elapsed since _lastBlock.
            // 3. Apply EMA formula: newEMA = oldEMA * (1 - alpha) + newValue * alpha
            //    where alpha depends on time elapsed and a smoothing factor.
            // 4. Use RateLimiter (once integrated) to check bounds (emaMin, emaMax).
            // 5. Update _totalBorrowEMA and _lastBlock.

        // Placeholder logic:
        // uint40 currentBlock = uint40(block.number);
        // if (currentBlock == _lastBlock) {
        // No blocks passed, no EMA update needed or possible if time-based
        //     return;
        // }

        // Example: Fetch "current value" for EMA (e.g., current buffer or a proxy for borrow rate)
        // uint256 currentValueForEma = currentBufferAmount; // This is a simplification

        // --- Actual EMA calculation would be more complex ---
        // uint120 newCalculatedEMA = _calculateEMA(_totalBorrowEMA, currentValueForEma, currentBlock - _lastBlock);

        // if (newCalculatedEMA < emaMin || newCalculatedEMA > emaMax) {
        //     revert EmaOutOfBounds(newCalculatedEMA, emaMin, emaMax);
        // }
        // _totalBorrowEMA = newCalculatedEMA;
        // _lastBlock = currentBlock;

        // emit EMACalculated(_totalBorrowEMA, currentBlock);
    }

    /**
     * @inheritdoc ISubsidyDistributor
     * @dev Uses "yield since last push" for `yield` in calculation.
     * `dIdx = (yield << 64).mulDiv512(1e18, ema)`. (Requires FullMath512.sol)
     * `ema` here refers to `totalBorrowEMA_`.
     */
    function pushIndex() external override nonReentrant {
        revert NotImplemented(); // TODO: Implement pushIndex logic with FullMath512
            // TODO: Potentially add access control (e.g., only BountyKeeper or owner) if not public.
            // Call lazyEMA first to ensure EMA is up-to-date if it's not called frequently elsewhere.
            // lazyEMA(); // Uncomment if EMA updates are primarily driven by pushIndex

        // uint256 yieldToProcess = yieldSinceLastPush;
        // if (yieldToProcess == 0) {
        // No yield to process, no index change
        // emit IndexPushed(globalIndex, 0, 0); // Optional: emit event even if no change
        //     return;
        // }

        // --- Placeholder for dIdx calculation ---
        // This requires FullMath512.mulDiv512 and a proper EMA value.
        // uint256 dIdx_calc = FullMath512.mulDiv512(yieldToProcess << 64, ONE_1E18, uint256(_totalBorrowEMA));
        // For now, a simplified dIdx calculation (NOT PRODUCTION READY):
        // uint256 dIdx_temp_placeholder =
        // (yieldToProcess << 64) / (_totalBorrowEMA > 0 ? uint256(_totalBorrowEMA) : (1 << 64)); // Avoid division by zero

        // if (dIdx_temp_placeholder > deltaIdxMax) {
        //     revert IndexUpdateOverflow(dIdx_temp_placeholder, deltaIdxMax);
        // }

        // uint128 dIdx = uint128(dIdx_temp_placeholder); // Safe cast after check

        // globalIndex += dIdx;
        // yieldSinceLastPush = 0;
        // _lastPushTimestamp = block.timestamp;

        // emit IndexPushed(globalIndex, dIdx, yieldToProcess);
    }

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function accrueUser(address userAddr, uint256 newWeight) external override nonReentrant {
        // TODO: Add RootGuardian snapshotId verification if required for weight updates.
        // e.g., require(rootGuardian.isValidSnapshot(_users[userAddr].snapshotId), "Invalid snapshot");

        User storage currentUser = _users[userAddr];
        uint128 currentGlobalIndex = globalIndex; // Cache globalIndex

        if (currentUser.index64x64 != 0 && currentUser.index64x64 < currentGlobalIndex) {
            // Calculate accrued rewards since last interaction
            // accruedAmount = weight * (globalIndex - user.index64x64) / (1 << 64) (approx)
            // The exact formula depends on how index and weight translate to rewards.
            // Assuming index is Q64.64 and weight is a simple multiplier.
            uint256 indexDiff = uint256(currentGlobalIndex - currentUser.index64x64);
            uint128 accruedAmount = uint128((uint256(currentUser.weight) * indexDiff) >> 64);
            currentUser.accrued += accruedAmount;
            emit UserAccrued(userAddr, currentUser.weight, accruedAmount); // Emits with old weight before update
        }

        currentUser.index64x64 = uint64(currentGlobalIndex); // Update user's index to current global
        currentUser.weight = uint32(newWeight); // Update weight
            // TODO: currentUser.snapshotId = rootGuardian.getCurrentEpochId(); // Update snapshotId

        // Emit UserAccrued again if weight change itself implies an accrual event or if preferred
        // For simplicity, one event after calculation is often sufficient.
    }

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function claimRewards(address userAddr) external override nonReentrant returns (uint256 claimedAmount) {
        User storage currentUser = _users[userAddr];
        uint128 currentGlobalIndex = globalIndex;

        // Accrue any pending rewards first
        if (currentUser.index64x64 != 0 && currentUser.index64x64 < currentGlobalIndex) {
            uint256 indexDiff = uint256(currentGlobalIndex - currentUser.index64x64);
            uint128 accruedAmountUpdate = uint128((uint256(currentUser.weight) * indexDiff) >> 64);
            currentUser.accrued += accruedAmountUpdate;
            // No UserAccrued event here as it's part of a claim
        }
        currentUser.index64x64 = uint64(currentGlobalIndex); // Update user's index

        claimedAmount = uint256(currentUser.accrued);
        if (claimedAmount == 0) {
            // No rewards to claim
            return 0;
        }

        if (claimedAmount > currentBufferAmount) {
            // This should ideally not happen if buffer management is correct
            // Or, it implies rewards are sourced from somewhere else too / buffer is just for new yield
            revert InsufficientAccruedRewards(userAddr, claimedAmount, currentBufferAmount); // Or a more generic "InsufficientBuffer"
        }

        currentUser.accrued = 0;
        currentBufferAmount -= claimedAmount; // Decrease buffer by claimed amount

        underlyingAsset.safeTransfer(userAddr, claimedAmount);

        emit RewardsClaimed(userAddr, claimedAmount);
        return claimedAmount;
    }

    // --- View Functions ---

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function getBufferAmount() external view override returns (uint256) {
        return currentBufferAmount;
    }

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function getLastPushTimestamp() external view override returns (uint256) {
        return _lastPushTimestamp;
    }

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function users(address userAddress) external view override returns (User memory userData) {
        return _users[userAddress];
    }

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function totalBorrowEMA() external view override returns (uint120 totalBorrowEMA_) {
        return _totalBorrowEMA;
    }

    /**
     * @inheritdoc ISubsidyDistributor
     */
    function lastBlock() external view override returns (uint40 lastBlock_) {
        return _lastBlock;
    }

    // --- Admin Functions ---

    /**
     * @notice Updates the MarketVault contract address.
     * @dev Only callable by the owner.
     * @param _newMarketVault The address of the new MarketVault contract.
     */
    function setMarketVault(address _newMarketVault) external onlyOwner {
        if (_newMarketVault == address(0)) revert AddressZero();
        marketVault = IMarketVault(_newMarketVault);
        // TODO: Add event
    }

    /**
     * @notice Updates the RootGuardian contract address.
     * @dev Only callable by the owner.
     * @param _newRootGuardian The address of the new RootGuardian contract.
     */
    // function setRootGuardian(address _newRootGuardian) external onlyOwner {
    //     if (_newRootGuardian == address(0)) revert AddressZero();
    //     rootGuardian = IRootGuardian(_newRootGuardian);
    //     // TODO: Add event
    // }

    /**
     * @notice Updates the deltaIdxMax parameter.
     * @dev Only callable by the owner.
     * @param _newDeltaIdxMax The new maximum allowed change in index per push.
     */
    function setDeltaIdxMax(uint256 _newDeltaIdxMax) external onlyOwner {
        if (_newDeltaIdxMax == 0) revert InvalidAmount();
        deltaIdxMax = _newDeltaIdxMax;
        // TODO: Add event
    }

    /**
     * @notice Updates the EMA bounds.
     * @dev Only callable by the owner.
     * @param _newEmaMin The new minimum EMA value.
     * @param _newEmaMax The new maximum EMA value.
     */
    function setEmaBounds(uint256 _newEmaMin, uint256 _newEmaMax) external onlyOwner {
        if (_newEmaMin == 0 || _newEmaMax == 0 || _newEmaMin >= _newEmaMax) revert InvalidAmount();
        emaMin = _newEmaMin;
        emaMax = _newEmaMax;
        // TODO: Add event
    }

    /**
     * @notice Allows the owner to withdraw any underlyingAsset accidentally sent to this contract,
     * or to recover funds in an emergency, provided it doesn't deplete the tracked buffer.
     * @dev This is a sensitive function and should be used with extreme caution.
     * It should not allow withdrawing more than `balanceOf(this) - currentBufferAmount`.
     * @param amount The amount of underlyingAsset to withdraw.
     * @param recipient The address to send the withdrawn tokens to.
     */
    function emergencyWithdraw(uint256 amount, address recipient) external onlyOwner {
        if (recipient == address(0)) revert AddressZero();
        if (amount == 0) revert InvalidAmount();

        uint256 contractBalance = underlyingAsset.balanceOf(address(this));
        uint256 withdrawableBalance = contractBalance > currentBufferAmount ? contractBalance - currentBufferAmount : 0;

        if (amount > withdrawableBalance) {
            revert InvalidAmount(); // Cannot withdraw more than untracked balance
        }
        underlyingAsset.safeTransfer(recipient, amount);
        // TODO: Add event
    }
}
