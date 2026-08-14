// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__Unauthorized,
    Arcadia__ValueOverflow,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { ArcadiaTypes } from "../types/ArcadiaTypes.sol";

/// @notice Minimal timelock for Arcadia parameter and module updates.
contract ArcadiaTimelock is ArcadiaRoles {
    struct Operation {
        bytes32 id;
        address target;
        uint256 value;
        bytes data;
        bytes32 predecessor;
        bytes32 salt;
        uint64 queuedAt;
        uint64 executableAt;
        bool executed;
        bool cancelled;
    }

    uint64 public minDelay;
    uint64 public gracePeriod;

    mapping(bytes32 => Operation) private _operations;
    mapping(bytes32 => bool) public done;

    event MinDelayUpdated(uint64 previousDelay, uint64 newDelay);
    event GracePeriodUpdated(uint64 previousGracePeriod, uint64 newGracePeriod);
    event OperationQueued(
        bytes32 indexed id,
        address indexed target,
        uint256 value,
        bytes32 predecessor,
        bytes32 salt,
        uint64 executableAt
    );
    event OperationCancelled(bytes32 indexed id);
    event OperationExecuted(bytes32 indexed id, address indexed target, uint256 value);

    constructor(address admin, uint64 minDelay_, uint64 gracePeriod_) ArcadiaRoles(admin) {
        if (minDelay_ == 0 || gracePeriod_ == 0) revert Arcadia__ZeroAmount();
        minDelay = minDelay_;
        gracePeriod = gracePeriod_;
        _grantInitialRole(ArcadiaTypes.GOVERNOR_ROLE, admin);
        _grantInitialRole(ArcadiaTypes.GUARDIAN_ROLE, admin);
    }

    receive() external payable { }

    function hashOperation(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(target, value, data, predecessor, salt));
    }

    function schedule(
        address target,
        uint256 value,
        bytes calldata data,
        bytes32 predecessor,
        bytes32 salt,
        uint64 delay
    ) external onlyRole(ArcadiaTypes.GOVERNOR_ROLE) returns (bytes32 id) {
        if (target == address(0)) revert Arcadia__ZeroAddress();
        uint64 effectiveDelay = delay < minDelay ? minDelay : delay;
        id = hashOperation(target, value, data, predecessor, salt);
        Operation storage operation_ = _operations[id];
        if (operation_.queuedAt != 0 && !operation_.cancelled) {
            revert Arcadia__Unauthorized(bytes32("OPERATION_EXISTS"), msg.sender);
        }

        uint256 executionTimestamp = block.timestamp + effectiveDelay;
        if (executionTimestamp > type(uint64).max) {
            revert Arcadia__ValueOverflow(executionTimestamp);
        }
        uint64 executableAt = uint64(executionTimestamp);
        _operations[id] = Operation({
            id: id,
            target: target,
            value: value,
            data: data,
            predecessor: predecessor,
            salt: salt,
            queuedAt: uint64(block.timestamp),
            executableAt: executableAt,
            executed: false,
            cancelled: false
        });

        emit OperationQueued(id, target, value, predecessor, salt, executableAt);
    }

    function cancel(bytes32 id) external onlyRole(ArcadiaTypes.GUARDIAN_ROLE) {
        Operation storage operation_ = _operations[id];
        if (operation_.queuedAt == 0 || operation_.executed || operation_.cancelled) {
            revert Arcadia__Unauthorized(bytes32("OPERATION_STATE"), msg.sender);
        }
        operation_.cancelled = true;
        emit OperationCancelled(id);
    }

    function execute(bytes32 id) external payable returns (bytes memory result) {
        Operation storage operation_ = _operations[id];
        _requireReady(operation_);
        if (operation_.predecessor != bytes32(0) && !done[operation_.predecessor]) {
            revert Arcadia__Unauthorized(bytes32("PREDECESSOR"), msg.sender);
        }

        operation_.executed = true;
        done[id] = true;
        (bool success, bytes memory returndata) =
            operation_.target.call{ value: operation_.value }(operation_.data);
        if (!success) {
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        }

        emit OperationExecuted(id, operation_.target, operation_.value);
        return returndata;
    }

    function updateDelay(uint64 newDelay) external {
        if (msg.sender != address(this)) {
            revert Arcadia__Unauthorized(bytes32("TIMELOCK"), msg.sender);
        }
        if (newDelay == 0) revert Arcadia__ZeroAmount();
        uint64 previous = minDelay;
        minDelay = newDelay;
        emit MinDelayUpdated(previous, newDelay);
    }

    function updateGracePeriod(uint64 newGracePeriod) external {
        if (msg.sender != address(this)) {
            revert Arcadia__Unauthorized(bytes32("TIMELOCK"), msg.sender);
        }
        if (newGracePeriod == 0) revert Arcadia__ZeroAmount();
        uint64 previous = gracePeriod;
        gracePeriod = newGracePeriod;
        emit GracePeriodUpdated(previous, newGracePeriod);
    }

    function operation(bytes32 id) external view returns (Operation memory) {
        return _operations[id];
    }

    function isOperation(bytes32 id) external view returns (bool) {
        return _operations[id].queuedAt != 0;
    }

    function isReady(bytes32 id) external view returns (bool) {
        Operation memory operation_ = _operations[id];
        if (operation_.queuedAt == 0 || operation_.executed || operation_.cancelled) return false;
        if (block.timestamp < operation_.executableAt) return false;
        return block.timestamp <= uint256(operation_.executableAt) + gracePeriod;
    }

    function isExpired(bytes32 id) external view returns (bool) {
        Operation memory operation_ = _operations[id];
        if (operation_.queuedAt == 0 || operation_.executed || operation_.cancelled) return false;
        return block.timestamp > uint256(operation_.executableAt) + gracePeriod;
    }

    function _requireReady(Operation memory operation_) internal view {
        if (operation_.queuedAt == 0 || operation_.executed || operation_.cancelled) {
            revert Arcadia__Unauthorized(bytes32("OPERATION_STATE"), msg.sender);
        }
        if (block.timestamp < operation_.executableAt) {
            revert Arcadia__Unauthorized(bytes32("OPERATION_EARLY"), msg.sender);
        }
        if (block.timestamp > uint256(operation_.executableAt) + gracePeriod) {
            revert Arcadia__Unauthorized(bytes32("OPERATION_EXPIRED"), msg.sender);
        }
    }
}
