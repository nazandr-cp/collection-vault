// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Roles} from "./Roles.sol";

/**
 * @title CrossContractSecurity
 * @dev Enhanced security utilities for cross-contract interactions
 * @dev Provides circuit breakers, rate limiting, and validation layers
 */
abstract contract CrossContractSecurity is AccessControl, ReentrancyGuard {
    // Circuit breaker states
    enum CircuitState {
        CLOSED,
        OPEN,
        HALF_OPEN
    }

    // Rate limiting structure
    struct RateLimit {
        uint256 windowStart;
        uint256 requestCount;
        uint256 maxRequests;
        uint256 windowDuration;
    }

    // Circuit breaker structure
    struct CircuitBreaker {
        CircuitState state;
        uint256 failureCount;
        uint256 lastFailureTime;
        uint256 failureThreshold;
        uint256 timeout;
        uint256 halfOpenMaxCalls;
        uint256 halfOpenCallCount;
    }

    // Contract validation structure
    struct ContractValidation {
        bool isValidated;
        bytes32 expectedCodeHash;
        uint256 lastValidated;
        uint256 validationExpiry;
    }

    // Storage
    mapping(bytes32 => CircuitBreaker) internal circuitBreakers;
    mapping(address => mapping(bytes4 => RateLimit)) internal rateLimits;
    mapping(address => ContractValidation) internal contractValidations;
    mapping(address => uint256) internal maxTransferAmounts;
    mapping(address => uint256) internal lastLargeTransfer;

    // Constants
    uint256 public constant DEFAULT_FAILURE_THRESHOLD = 5;
    uint256 public constant DEFAULT_TIMEOUT = 300; // 5 minutes
    uint256 public constant DEFAULT_RATE_WINDOW = 3600; // 1 hour
    uint256 public constant DEFAULT_MAX_REQUESTS = 100;
    uint256 public constant LARGE_TRANSFER_COOLDOWN = 1800; // 30 minutes
    uint256 public constant CONTRACT_VALIDATION_EXPIRY = 86400; // 24 hours

    // Events
    event CircuitBreakerTripped(bytes32 indexed circuitId, uint256 timestamp);
    event CircuitBreakerReset(bytes32 indexed circuitId, uint256 timestamp);
    event RateLimitExceeded(address indexed caller, bytes4 indexed selector, uint256 timestamp);
    event LargeTransferDetected(address indexed from, address indexed to, uint256 amount, uint256 timestamp);
    event ContractValidationFailed(address indexed contractAddr, bytes32 expected, bytes32 actual);
    event SuspiciousActivityDetected(address indexed actor, string reason, uint256 timestamp);

    // Errors
    error CrossContractSecurity__CircuitBreakerOpen(bytes32 circuitId);
    error CrossContractSecurity__RateLimitExceeded(address caller, bytes4 selector);
    error CrossContractSecurity__ContractValidationFailed(address contractAddr);
    error CrossContractSecurity__TransferAmountExceeded(uint256 amount, uint256 limit);
    error CrossContractSecurity__TransferCooldownActive(uint256 remainingTime);
    error CrossContractSecurity__InvalidAddress();
    error CrossContractSecurity__InvalidParameters();

    /**
     * @dev Initialize circuit breaker for a specific operation
     */
    function _initCircuitBreaker(bytes32 circuitId, uint256 failureThreshold, uint256 timeout) internal {
        circuitBreakers[circuitId] = CircuitBreaker({
            state: CircuitState.CLOSED,
            failureCount: 0,
            lastFailureTime: 0,
            failureThreshold: failureThreshold > 0 ? failureThreshold : DEFAULT_FAILURE_THRESHOLD,
            timeout: timeout > 0 ? timeout : DEFAULT_TIMEOUT,
            halfOpenMaxCalls: 3,
            halfOpenCallCount: 0
        });
    }

    /**
     * @dev Initialize rate limiting for a contract/function combination
     */
    function _initRateLimit(address contractAddr, bytes4 selector, uint256 maxRequests, uint256 windowDuration)
        internal
    {
        rateLimits[contractAddr][selector] = RateLimit({
            windowStart: block.timestamp,
            requestCount: 0,
            maxRequests: maxRequests > 0 ? maxRequests : DEFAULT_MAX_REQUESTS,
            windowDuration: windowDuration > 0 ? windowDuration : DEFAULT_RATE_WINDOW
        });
    }

    /**
     * @dev Check and update circuit breaker state
     */
    modifier circuitBreakerProtected(bytes32 circuitId) {
        CircuitBreaker storage cb = circuitBreakers[circuitId];

        // Initialize if not exists
        if (cb.failureThreshold == 0) {
            _initCircuitBreaker(circuitId, DEFAULT_FAILURE_THRESHOLD, DEFAULT_TIMEOUT);
            cb = circuitBreakers[circuitId];
        }

        // Check circuit state
        if (cb.state == CircuitState.OPEN) {
            if (block.timestamp >= cb.lastFailureTime + cb.timeout) {
                cb.state = CircuitState.HALF_OPEN;
                cb.halfOpenCallCount = 0;
            } else {
                revert CrossContractSecurity__CircuitBreakerOpen(circuitId);
            }
        }

        if (cb.state == CircuitState.HALF_OPEN && cb.halfOpenCallCount >= cb.halfOpenMaxCalls) {
            revert CrossContractSecurity__CircuitBreakerOpen(circuitId);
        }

        if (cb.state == CircuitState.HALF_OPEN) {
            cb.halfOpenCallCount++;
        }

        _;

        // If we reach here, the call was successful
        if (cb.state == CircuitState.HALF_OPEN) {
            cb.state = CircuitState.CLOSED;
            cb.failureCount = 0;
            emit CircuitBreakerReset(circuitId, block.timestamp);
        }
    }

    /**
     * @dev Record circuit breaker failure
     */
    function _recordCircuitFailure(bytes32 circuitId) internal {
        CircuitBreaker storage cb = circuitBreakers[circuitId];
        cb.failureCount++;
        cb.lastFailureTime = block.timestamp;

        if (cb.failureCount >= cb.failureThreshold) {
            cb.state = CircuitState.OPEN;
            emit CircuitBreakerTripped(circuitId, block.timestamp);
        }
    }

    /**
     * @dev Rate limiting protection
     */
    modifier rateLimited(address contractAddr, bytes4 selector) {
        RateLimit storage rl = rateLimits[contractAddr][selector];

        // Initialize if not exists
        if (rl.maxRequests == 0) {
            _initRateLimit(contractAddr, selector, DEFAULT_MAX_REQUESTS, DEFAULT_RATE_WINDOW);
            rl = rateLimits[contractAddr][selector];
        }

        // Reset window if expired
        if (block.timestamp >= rl.windowStart + rl.windowDuration) {
            rl.windowStart = block.timestamp;
            rl.requestCount = 0;
        }

        // Check rate limit
        if (rl.requestCount >= rl.maxRequests) {
            emit RateLimitExceeded(msg.sender, selector, block.timestamp);
            revert CrossContractSecurity__RateLimitExceeded(msg.sender, selector);
        }

        rl.requestCount++;
        _;
    }

    /**
     * @dev Validate external contract hasn't changed
     */
    modifier contractValidated(address contractAddr) {
        ContractValidation storage cv = contractValidations[contractAddr];

        if (cv.isValidated && block.timestamp <= cv.lastValidated + cv.validationExpiry) {
            // Check if code hash still matches
            bytes32 currentCodeHash = keccak256(abi.encodePacked(contractAddr.code));
            if (currentCodeHash != cv.expectedCodeHash) {
                emit ContractValidationFailed(contractAddr, cv.expectedCodeHash, currentCodeHash);
                revert CrossContractSecurity__ContractValidationFailed(contractAddr);
            }
        }
        _;
    }

    /**
     * @dev Large transfer protection
     */
    modifier largeTransferProtected(address to, uint256 amount) {
        uint256 maxAmount = maxTransferAmounts[to];
        if (maxAmount > 0 && amount > maxAmount) {
            revert CrossContractSecurity__TransferAmountExceeded(amount, maxAmount);
        }

        // Check cooldown for large transfers
        if (amount > maxAmount / 2 && lastLargeTransfer[msg.sender] + LARGE_TRANSFER_COOLDOWN > block.timestamp) {
            revert CrossContractSecurity__TransferCooldownActive(
                lastLargeTransfer[msg.sender] + LARGE_TRANSFER_COOLDOWN - block.timestamp
            );
        }

        if (amount > maxAmount / 2) {
            lastLargeTransfer[msg.sender] = block.timestamp;
            emit LargeTransferDetected(msg.sender, to, amount, block.timestamp);
        }

        _;
    }

    /**
     * @dev Admin functions for security configuration
     */
    function setMaxTransferAmount(address target, uint256 maxAmount) external onlyRole(Roles.ADMIN_ROLE) {
        if (target == address(0)) revert CrossContractSecurity__InvalidAddress();
        maxTransferAmounts[target] = maxAmount;
    }

    function validateContract(address contractAddr) external onlyRole(Roles.ADMIN_ROLE) {
        if (contractAddr == address(0)) revert CrossContractSecurity__InvalidAddress();

        bytes32 codeHash = keccak256(abi.encodePacked(contractAddr.code));
        contractValidations[contractAddr] = ContractValidation({
            isValidated: true,
            expectedCodeHash: codeHash,
            lastValidated: block.timestamp,
            validationExpiry: CONTRACT_VALIDATION_EXPIRY
        });
    }

    function resetCircuitBreaker(bytes32 circuitId) external onlyRole(Roles.GUARDIAN_ROLE) {
        CircuitBreaker storage cb = circuitBreakers[circuitId];
        cb.state = CircuitState.CLOSED;
        cb.failureCount = 0;
        cb.halfOpenCallCount = 0;
        emit CircuitBreakerReset(circuitId, block.timestamp);
    }

    function updateRateLimit(address contractAddr, bytes4 selector, uint256 maxRequests, uint256 windowDuration)
        external
        onlyRole(Roles.ADMIN_ROLE)
    {
        if (contractAddr == address(0)) revert CrossContractSecurity__InvalidAddress();
        if (maxRequests == 0 || windowDuration == 0) revert CrossContractSecurity__InvalidParameters();

        _initRateLimit(contractAddr, selector, maxRequests, windowDuration);
    }

    /**
     * @dev Emergency override for circuit breakers
     */
    function emergencyOverride(bytes32 circuitId) external onlyRole(Roles.GUARDIAN_ROLE) {
        CircuitBreaker storage cb = circuitBreakers[circuitId];
        cb.state = CircuitState.CLOSED;
        cb.failureCount = 0;
        emit CircuitBreakerReset(circuitId, block.timestamp);
        emit SuspiciousActivityDetected(msg.sender, "Emergency circuit breaker override", block.timestamp);
    }

    /**
     * @dev Get circuit breaker status
     */
    function getCircuitBreakerStatus(bytes32 circuitId)
        external
        view
        returns (CircuitState state, uint256 failureCount, uint256 lastFailureTime)
    {
        CircuitBreaker storage cb = circuitBreakers[circuitId];
        return (cb.state, cb.failureCount, cb.lastFailureTime);
    }

    /**
     * @dev Get rate limit status
     */
    function getRateLimitStatus(address contractAddr, bytes4 selector)
        external
        view
        returns (uint256 requestCount, uint256 maxRequests, uint256 windowStart, uint256 windowDuration)
    {
        RateLimit storage rl = rateLimits[contractAddr][selector];
        return (rl.requestCount, rl.maxRequests, rl.windowStart, rl.windowDuration);
    }
}
