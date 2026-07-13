// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__InsufficientAssets,
    Arcadia__InvalidTranche,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { ArcadiaTypes, Tranche } from "../types/ArcadiaTypes.sol";

/// @notice Internal reserve ledger for accounting reconciliations and operator reports.
contract ReserveLedger is ArcadiaRoles {
    enum ReserveKind {
        Idle,
        StrategyDebt,
        PendingHarvest,
        PendingLoss,
        Fees,
        Emergency
    }

    struct ReserveCheckpoint {
        uint256 id;
        uint256 totalReserves;
        uint256 seniorReserves;
        uint256 mezzanineReserves;
        uint256 juniorReserves;
        uint64 timestamp;
        bytes32 noteHash;
    }

    mapping(uint8 => mapping(uint8 => uint256)) private _reserves;
    mapping(uint256 => ReserveCheckpoint) private _checkpoints;
    uint256 public latestCheckpointId;

    event ReserveCredited(Tranche indexed tranche, ReserveKind indexed kind, uint256 amount);
    event ReserveDebited(Tranche indexed tranche, ReserveKind indexed kind, uint256 amount);
    event ReserveMoved(
        Tranche indexed fromTranche,
        ReserveKind indexed fromKind,
        Tranche indexed toTranche,
        ReserveKind toKind,
        uint256 amount
    );
    event ReserveCheckpointCreated(uint256 indexed id, uint256 totalReserves, bytes32 noteHash);

    constructor(address admin) ArcadiaRoles(admin) {
        if (admin == address(0)) revert Arcadia__ZeroAddress();
        _grantInitialRole(ArcadiaTypes.KEEPER_ROLE, admin);
    }

    function credit(Tranche tranche, ReserveKind kind, uint256 amount)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
    {
        if (amount == 0) revert Arcadia__ZeroAmount();
        uint8 trancheId = _idx(tranche);
        _reserves[trancheId][uint8(kind)] += amount;
        emit ReserveCredited(tranche, kind, amount);
    }

    function debit(Tranche tranche, ReserveKind kind, uint256 amount)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
    {
        if (amount == 0) revert Arcadia__ZeroAmount();
        uint8 trancheId = _idx(tranche);
        uint8 kindId = uint8(kind);
        uint256 balance = _reserves[trancheId][kindId];
        if (amount > balance) revert Arcadia__InsufficientAssets(amount, balance);
        _reserves[trancheId][kindId] = balance - amount;
        emit ReserveDebited(tranche, kind, amount);
    }

    function moveReserve(
        Tranche fromTranche,
        ReserveKind fromKind,
        Tranche toTranche,
        ReserveKind toKind,
        uint256 amount
    ) external onlyRole(ArcadiaTypes.KEEPER_ROLE) {
        if (amount == 0) revert Arcadia__ZeroAmount();
        uint8 fromTrancheId = _idx(fromTranche);
        uint8 toTrancheId = _idx(toTranche);
        uint8 fromKindId = uint8(fromKind);
        uint8 toKindId = uint8(toKind);
        uint256 balance = _reserves[fromTrancheId][fromKindId];
        if (amount > balance) revert Arcadia__InsufficientAssets(amount, balance);

        _reserves[fromTrancheId][fromKindId] = balance - amount;
        _reserves[toTrancheId][toKindId] += amount;

        emit ReserveMoved(fromTranche, fromKind, toTranche, toKind, amount);
    }

    function checkpoint(bytes32 noteHash)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
        returns (uint256 id)
    {
        uint256 senior = trancheReserveTotal(Tranche.Senior);
        uint256 mezzanine = trancheReserveTotal(Tranche.Mezzanine);
        uint256 junior = trancheReserveTotal(Tranche.Junior);
        uint256 total = senior + mezzanine + junior;

        id = ++latestCheckpointId;
        _checkpoints[id] = ReserveCheckpoint({
            id: id,
            totalReserves: total,
            seniorReserves: senior,
            mezzanineReserves: mezzanine,
            juniorReserves: junior,
            timestamp: uint64(block.timestamp),
            noteHash: noteHash
        });

        emit ReserveCheckpointCreated(id, total, noteHash);
    }

    function reserveOf(Tranche tranche, ReserveKind kind) external view returns (uint256) {
        return _reserves[uint8(tranche)][uint8(kind)];
    }

    function checkpointAt(uint256 id) external view returns (ReserveCheckpoint memory) {
        return _checkpoints[id];
    }

    function trancheReserveTotal(Tranche tranche) public view returns (uint256 total) {
        uint8 trancheId = uint8(tranche);
        for (uint8 kind; kind <= uint8(ReserveKind.Emergency); ++kind) {
            total += _reserves[trancheId][kind];
        }
    }

    function reserveKindTotal(ReserveKind kind) public view returns (uint256 total) {
        uint8 kindId = uint8(kind);
        total += _reserves[uint8(Tranche.Senior)][kindId];
        total += _reserves[uint8(Tranche.Mezzanine)][kindId];
        total += _reserves[uint8(Tranche.Junior)][kindId];
    }

    function protocolReserveTotal() external view returns (uint256 total) {
        total += trancheReserveTotal(Tranche.Senior);
        total += trancheReserveTotal(Tranche.Mezzanine);
        total += trancheReserveTotal(Tranche.Junior);
    }

    function _idx(Tranche tranche) internal pure returns (uint8 id) {
        id = uint8(tranche);
        if (id > uint8(Tranche.Junior)) revert Arcadia__InvalidTranche(id);
    }
}
