// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__InvalidBps,
    Arcadia__PriceConfidenceLow,
    Arcadia__StrategyReportStale,
    Arcadia__Unauthorized,
    Arcadia__ValueOverflow,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ArcadiaTypes, Tranche } from "../types/ArcadiaTypes.sol";

/// @notice NAV observation router for off-chain pricing and risk attestations.
contract ArcadiaNavOracle is ArcadiaRoles {
    using FixedPointMath for uint256;

    struct NavSource {
        bytes32 id;
        address reporter;
        uint16 minConfidenceBps;
        uint64 heartbeat;
        bool active;
        string label;
    }

    struct NavObservation {
        bytes32 sourceId;
        uint256 nav;
        uint256 liquidAssets;
        uint256 estimatedAssets;
        uint256 confidenceBps;
        uint64 observedAt;
        bytes32 payloadHash;
    }

    bytes32[] private _sourceIds;
    mapping(bytes32 => NavSource) private _sources;
    mapping(bytes32 => NavObservation) private _latest;
    mapping(uint8 => bytes32) public preferredSourceForTranche;

    event SourceAdded(bytes32 indexed id, address indexed reporter, string label);
    event SourceUpdated(
        bytes32 indexed id,
        address indexed reporter,
        uint16 minConfidenceBps,
        uint64 heartbeat,
        bool active
    );
    event ObservationSubmitted(
        bytes32 indexed id,
        uint256 nav,
        uint256 liquidAssets,
        uint256 estimatedAssets,
        uint256 confidenceBps,
        bytes32 payloadHash
    );
    event PreferredSourceUpdated(Tranche indexed tranche, bytes32 indexed sourceId);

    constructor(address admin) ArcadiaRoles(admin) {
        _grantInitialRole(ArcadiaTypes.RISK_MANAGER_ROLE, admin);
        _grantInitialRole(ArcadiaTypes.REPORTER_ROLE, admin);
    }

    function addSource(
        bytes32 id,
        address reporter,
        uint16 minConfidenceBps,
        uint64 heartbeat,
        string calldata label
    ) external onlyRole(ArcadiaTypes.RISK_MANAGER_ROLE) {
        if (id == bytes32(0) || reporter == address(0)) {
            revert Arcadia__ZeroAddress();
        }
        if (_sources[id].id != bytes32(0)) {
            revert Arcadia__Unauthorized(bytes32("SOURCE_EXISTS"), msg.sender);
        }
        _validateSource(minConfidenceBps, heartbeat);
        _sources[id] = NavSource({
            id: id,
            reporter: reporter,
            minConfidenceBps: minConfidenceBps,
            heartbeat: heartbeat,
            active: true,
            label: label
        });
        _sourceIds.push(id);
        emit SourceAdded(id, reporter, label);
    }

    function updateSource(
        bytes32 id,
        address reporter,
        uint16 minConfidenceBps,
        uint64 heartbeat,
        bool active
    ) external onlyRole(ArcadiaTypes.RISK_MANAGER_ROLE) {
        _requireSource(id);
        if (reporter == address(0)) revert Arcadia__ZeroAddress();
        _validateSource(minConfidenceBps, heartbeat);
        NavSource storage source_ = _sources[id];
        source_.reporter = reporter;
        source_.minConfidenceBps = minConfidenceBps;
        source_.heartbeat = heartbeat;
        source_.active = active;
        emit SourceUpdated(id, reporter, minConfidenceBps, heartbeat, active);
    }

    function setPreferredSource(Tranche tranche, bytes32 sourceId)
        external
        onlyRole(ArcadiaTypes.RISK_MANAGER_ROLE)
    {
        _requireSource(sourceId);
        preferredSourceForTranche[uint8(tranche)] = sourceId;
        emit PreferredSourceUpdated(tranche, sourceId);
    }

    function submitObservation(
        bytes32 sourceId,
        uint256 nav,
        uint256 liquidAssets,
        uint256 estimatedAssets,
        uint256 confidenceBps,
        bytes32 payloadHash
    ) external {
        NavSource memory source_ = _requireSource(sourceId);
        if (!source_.active) revert Arcadia__Unauthorized(bytes32("SOURCE_INACTIVE"), msg.sender);
        if (msg.sender != source_.reporter && !hasRole(ArcadiaTypes.REPORTER_ROLE, msg.sender)) {
            revert Arcadia__Unauthorized(ArcadiaTypes.REPORTER_ROLE, msg.sender);
        }
        if (nav == 0) revert Arcadia__ZeroAmount();
        if (confidenceBps < source_.minConfidenceBps) {
            revert Arcadia__PriceConfidenceLow(confidenceBps, source_.minConfidenceBps);
        }
        if (confidenceBps > ArcadiaTypes.BPS) revert Arcadia__InvalidBps(confidenceBps);

        _latest[sourceId] = NavObservation({
            sourceId: sourceId,
            nav: nav,
            liquidAssets: liquidAssets,
            estimatedAssets: estimatedAssets,
            confidenceBps: confidenceBps,
            observedAt: uint64(block.timestamp),
            payloadHash: payloadHash
        });

        emit ObservationSubmitted(
            sourceId, nav, liquidAssets, estimatedAssets, confidenceBps, payloadHash
        );
    }

    function latestObservation(bytes32 sourceId) external view returns (NavObservation memory) {
        _requireSource(sourceId);
        return _latest[sourceId];
    }

    function requireFresh(bytes32 sourceId)
        public
        view
        returns (NavObservation memory observation)
    {
        NavSource memory source_ = _requireSource(sourceId);
        observation = _latest[sourceId];
        if (observation.observedAt == 0) {
            revert Arcadia__StrategyReportStale(address(0), 0, source_.heartbeat);
        }
        if (block.timestamp > uint256(observation.observedAt) + source_.heartbeat) {
            revert Arcadia__StrategyReportStale(
                address(0), observation.observedAt, source_.heartbeat
            );
        }
    }

    function trancheNav(Tranche tranche) external view returns (uint256 nav) {
        bytes32 sourceId = preferredSourceForTranche[uint8(tranche)];
        if (sourceId == bytes32(0)) revert Arcadia__ZeroAddress();
        nav = requireFresh(sourceId).nav;
    }

    function sourceCount() external view returns (uint256) {
        return _sourceIds.length;
    }

    function sourceAt(uint256 index) external view returns (bytes32) {
        return _sourceIds[index];
    }

    function source(bytes32 id) external view returns (NavSource memory) {
        return _requireSource(id);
    }

    function navPremiumBps(bytes32 sourceId) external view returns (int256 premiumBps) {
        NavObservation memory observation = requireFresh(sourceId);
        if (observation.liquidAssets == 0) return 0;
        if (observation.estimatedAssets >= observation.liquidAssets) {
            uint256 premium = observation.estimatedAssets - observation.liquidAssets;
            return _toInt256(FixedPointMath.ratioBps(premium, observation.liquidAssets));
        }
        uint256 discount = observation.liquidAssets - observation.estimatedAssets;
        return -_toInt256(FixedPointMath.ratioBps(discount, observation.liquidAssets));
    }

    function _requireSource(bytes32 id) internal view returns (NavSource memory source_) {
        source_ = _sources[id];
        if (source_.id == bytes32(0)) revert Arcadia__ZeroAddress();
    }

    function _validateSource(uint16 minConfidenceBps, uint64 heartbeat) internal pure {
        if (minConfidenceBps > ArcadiaTypes.BPS) revert Arcadia__InvalidBps(minConfidenceBps);
        if (heartbeat == 0) revert Arcadia__ZeroAmount();
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) revert Arcadia__ValueOverflow(value);
        return int256(value);
    }
}
