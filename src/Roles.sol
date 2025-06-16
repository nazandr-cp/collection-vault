// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Common role definitions used across the Collection Vault system
library Roles {
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant VAULT_ROLE = keccak256("VAULT_ROLE");
    bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 internal constant DEBT_SUBSIDIZER_ROLE = keccak256("DEBT_SUBSIDIZER_ROLE");
}
