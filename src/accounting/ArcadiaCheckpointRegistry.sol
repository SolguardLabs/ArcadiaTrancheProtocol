// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__CheckpointMismatch,
    Arcadia__ValueOverflow,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { IArcadiaVault } from "../interfaces/IArcadiaVault.sol";
import { ArcadiaTypes, ProtocolSnapshot, Tranche, TrancheState } from "../types/ArcadiaTypes.sol";

/// @notice Append-only evidence chain for reconciled vault state and approved configuration.
contract ArcadiaCheckpointRegistry is ArcadiaRoles {
    struct Checkpoint {
        uint256 sequence;
        bytes32 stateDigest;
        bytes32 navDigest;
        bytes32 configDigest;
        bytes32 previousDigest;
        bytes32 checkpointDigest;
        uint64 blockNumber;
        uint64 timestamp;
    }

    bytes32 public constant DOMAIN = keccak256("ARCADIA_CHECKPOINT_V1");

    IArcadiaVault public immutable vault;
    uint256 public latestSequence;
    bytes32 public latestCheckpointDigest;
    mapping(uint256 => Checkpoint) private _checkpoints;

    event CheckpointRecorded(
        uint256 indexed sequence,
        bytes32 indexed checkpointDigest,
        bytes32 indexed stateDigest,
        bytes32 navDigest,
        bytes32 configDigest
    );

    constructor(address admin, address vault_) ArcadiaRoles(admin) {
        if (vault_ == address(0)) revert Arcadia__ZeroAddress();
        vault = IArcadiaVault(vault_);
        _grantInitialRole(ArcadiaTypes.KEEPER_ROLE, admin);
    }

    function capture(bytes32 navDigest, bytes32 configDigest)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
        returns (Checkpoint memory checkpoint_)
    {
        if (navDigest == bytes32(0) || configDigest == bytes32(0)) {
            revert Arcadia__ZeroAmount();
        }
        if (block.number > type(uint64).max) revert Arcadia__ValueOverflow(block.number);
        if (block.timestamp > type(uint64).max) revert Arcadia__ValueOverflow(block.timestamp);

        uint256 sequence = latestSequence + 1;
        bytes32 stateDigest_ = currentStateDigest();
        bytes32 previousDigest = latestCheckpointDigest;
        bytes32 checkpointDigest = keccak256(
            abi.encode(
                DOMAIN,
                block.chainid,
                address(this),
                sequence,
                stateDigest_,
                navDigest,
                configDigest,
                previousDigest,
                block.number,
                block.timestamp,
                ArcadiaTypes.VERSION
            )
        );
        checkpoint_ = Checkpoint({
            sequence: sequence,
            stateDigest: stateDigest_,
            navDigest: navDigest,
            configDigest: configDigest,
            previousDigest: previousDigest,
            checkpointDigest: checkpointDigest,
            blockNumber: uint64(block.number),
            timestamp: uint64(block.timestamp)
        });
        _checkpoints[sequence] = checkpoint_;
        latestSequence = sequence;
        latestCheckpointDigest = checkpointDigest;
        emit CheckpointRecorded(sequence, checkpointDigest, stateDigest_, navDigest, configDigest);
    }

    function currentStateDigest() public view returns (bytes32) {
        ProtocolSnapshot memory protocol = vault.snapshot();
        TrancheState memory senior = vault.trancheState(Tranche.Senior);
        TrancheState memory mezzanine = vault.trancheState(Tranche.Mezzanine);
        TrancheState memory junior = vault.trancheState(Tranche.Junior);
        return keccak256(
            abi.encode(
                block.chainid,
                address(vault),
                protocol,
                senior,
                mezzanine,
                junior,
                ArcadiaTypes.VERSION
            )
        );
    }

    function checkpointAt(uint256 sequence) external view returns (Checkpoint memory) {
        return _checkpoints[sequence];
    }

    function requireCurrent(uint256 sequence)
        external
        view
        returns (Checkpoint memory checkpoint_)
    {
        checkpoint_ = _checkpoints[sequence];
        bytes32 observed = currentStateDigest();
        if (checkpoint_.stateDigest != observed) {
            revert Arcadia__CheckpointMismatch(checkpoint_.stateDigest, observed);
        }
    }

    function version() external pure returns (string memory) {
        return ArcadiaTypes.VERSION;
    }
}
