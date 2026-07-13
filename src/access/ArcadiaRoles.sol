// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Arcadia__InvalidRoleAdmin,
    Arcadia__RoleAlreadyGranted,
    Arcadia__RoleNotGranted,
    Arcadia__Unauthorized,
    Arcadia__ZeroAddress
} from "../errors/ArcadiaErrors.sol";

/// @notice Compact role manager used by Arcadia contracts.
contract ArcadiaRoles {
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    mapping(bytes32 => mapping(address => bool)) private _roles;
    mapping(bytes32 => bytes32) private _roleAdmins;

    event RoleAdminChanged(
        bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole
    );
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    constructor(address initialAdmin) {
        if (initialAdmin == address(0)) revert Arcadia__ZeroAddress();
        _roles[DEFAULT_ADMIN_ROLE][initialAdmin] = true;
        _roleAdmins[DEFAULT_ADMIN_ROLE] = DEFAULT_ADMIN_ROLE;
        emit RoleGranted(DEFAULT_ADMIN_ROLE, initialAdmin, msg.sender);
    }

    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role][account];
    }

    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        bytes32 admin = _roleAdmins[role];
        if (admin == bytes32(0) && role != DEFAULT_ADMIN_ROLE) return DEFAULT_ADMIN_ROLE;
        return admin;
    }

    function grantRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (account == address(0)) revert Arcadia__ZeroAddress();
        if (_roles[role][account]) revert Arcadia__RoleAlreadyGranted(role, account);
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }

    function revokeRole(bytes32 role, address account) external onlyRole(getRoleAdmin(role)) {
        if (!_roles[role][account]) revert Arcadia__RoleNotGranted(role, account);
        _roles[role][account] = false;
        emit RoleRevoked(role, account, msg.sender);
    }

    function renounceRole(bytes32 role) external {
        if (!_roles[role][msg.sender]) revert Arcadia__RoleNotGranted(role, msg.sender);
        _roles[role][msg.sender] = false;
        emit RoleRevoked(role, msg.sender, msg.sender);
    }

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (role == DEFAULT_ADMIN_ROLE && adminRole != DEFAULT_ADMIN_ROLE) {
            revert Arcadia__InvalidRoleAdmin(role, adminRole);
        }
        bytes32 previous = getRoleAdmin(role);
        _roleAdmins[role] = adminRole;
        emit RoleAdminChanged(role, previous, adminRole);
    }

    function _checkRole(bytes32 role, address account) internal view {
        if (!_roles[role][account]) revert Arcadia__Unauthorized(role, account);
    }

    function _grantInitialRole(bytes32 role, address account) internal {
        if (account == address(0)) revert Arcadia__ZeroAddress();
        if (_roles[role][account]) return;
        _roles[role][account] = true;
        emit RoleGranted(role, account, msg.sender);
    }
}
