// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__InvalidBps,
    Arcadia__InvalidTranche,
    Arcadia__LimitExceeded,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { ArcadiaTypes, Tranche } from "../types/ArcadiaTypes.sol";

/// @notice Parameter store for tranche-level operational limits.
contract TrancheParameterStore is ArcadiaRoles {
    struct TrancheLimits {
        uint128 minDeposit;
        uint128 maxDeposit;
        uint128 maxDailyInflow;
        uint128 maxDailyOutflow;
        uint16 targetWeightBps;
        uint16 warningCoverageBps;
        uint16 criticalCoverageBps;
        bool active;
    }

    struct FlowBucket {
        uint64 day;
        uint128 inflow;
        uint128 outflow;
    }

    mapping(uint8 => TrancheLimits) private _limits;
    mapping(uint8 => FlowBucket) private _buckets;

    event TrancheLimitsUpdated(
        Tranche indexed tranche,
        uint128 minDeposit,
        uint128 maxDeposit,
        uint128 maxDailyInflow,
        uint128 maxDailyOutflow,
        uint16 targetWeightBps,
        uint16 warningCoverageBps,
        uint16 criticalCoverageBps,
        bool active
    );
    event FlowRecorded(Tranche indexed tranche, uint256 inflow, uint256 outflow, uint64 day);
    event FlowBucketReset(Tranche indexed tranche, uint64 previousDay, uint64 newDay);

    constructor(address admin) ArcadiaRoles(admin) {
        if (admin == address(0)) revert Arcadia__ZeroAddress();
        _grantInitialRole(ArcadiaTypes.RISK_MANAGER_ROLE, admin);
        _setLimits(
            Tranche.Senior,
            TrancheLimits({
                minDeposit: 1 ether,
                maxDeposit: type(uint128).max,
                maxDailyInflow: type(uint128).max,
                maxDailyOutflow: type(uint128).max,
                targetWeightBps: 5000,
                warningCoverageBps: 3000,
                criticalCoverageBps: 1500,
                active: true
            })
        );
        _setLimits(
            Tranche.Mezzanine,
            TrancheLimits({
                minDeposit: 1 ether,
                maxDeposit: type(uint128).max,
                maxDailyInflow: type(uint128).max,
                maxDailyOutflow: type(uint128).max,
                targetWeightBps: 2500,
                warningCoverageBps: 1500,
                criticalCoverageBps: 750,
                active: true
            })
        );
        _setLimits(
            Tranche.Junior,
            TrancheLimits({
                minDeposit: 1 ether,
                maxDeposit: type(uint128).max,
                maxDailyInflow: type(uint128).max,
                maxDailyOutflow: type(uint128).max,
                targetWeightBps: 2500,
                warningCoverageBps: 0,
                criticalCoverageBps: 0,
                active: true
            })
        );
    }

    function setLimits(Tranche tranche, TrancheLimits calldata limits_)
        external
        onlyRole(ArcadiaTypes.RISK_MANAGER_ROLE)
    {
        _setLimits(tranche, limits_);
    }

    function limits(Tranche tranche) external view returns (TrancheLimits memory) {
        return _limits[_idx(tranche)];
    }

    function flowBucket(Tranche tranche) external view returns (FlowBucket memory) {
        return _buckets[_idx(tranche)];
    }

    function recordInflow(Tranche tranche, uint128 assets)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
    {
        if (assets == 0) revert Arcadia__ZeroAmount();
        uint8 id = _idx(tranche);
        _rollBucket(id);
        FlowBucket storage bucket = _buckets[id];
        TrancheLimits memory limit = _limits[id];
        uint256 resulting = uint256(bucket.inflow) + assets;
        if (resulting > limit.maxDailyInflow) {
            revert Arcadia__LimitExceeded(resulting, limit.maxDailyInflow);
        }
        bucket.inflow = uint128(resulting);
        emit FlowRecorded(tranche, assets, 0, bucket.day);
    }

    function recordOutflow(Tranche tranche, uint128 assets)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
    {
        if (assets == 0) revert Arcadia__ZeroAmount();
        uint8 id = _idx(tranche);
        _rollBucket(id);
        FlowBucket storage bucket = _buckets[id];
        TrancheLimits memory limit = _limits[id];
        uint256 resulting = uint256(bucket.outflow) + assets;
        if (resulting > limit.maxDailyOutflow) {
            revert Arcadia__LimitExceeded(resulting, limit.maxDailyOutflow);
        }
        bucket.outflow = uint128(resulting);
        emit FlowRecorded(tranche, 0, assets, bucket.day);
    }

    function validateDeposit(Tranche tranche, uint256 assets) external view returns (bool) {
        TrancheLimits memory limit = _limits[_idx(tranche)];
        if (!limit.active) return false;
        if (assets < limit.minDeposit) return false;
        if (assets > limit.maxDeposit) return false;
        FlowBucket memory bucket = _buckets[uint8(tranche)];
        if (bucket.day == _currentDay() && uint256(bucket.inflow) + assets > limit.maxDailyInflow) {
            return false;
        }
        return true;
    }

    function validateOutflow(Tranche tranche, uint256 assets) external view returns (bool) {
        TrancheLimits memory limit = _limits[_idx(tranche)];
        if (!limit.active) return false;
        FlowBucket memory bucket = _buckets[uint8(tranche)];
        if (bucket.day == _currentDay() && uint256(bucket.outflow) + assets > limit.maxDailyOutflow)
        {
            return false;
        }
        return true;
    }

    function coverageState(Tranche tranche, uint256 coverageBps)
        external
        view
        returns (uint8 state)
    {
        TrancheLimits memory limit = _limits[_idx(tranche)];
        if (coverageBps < limit.criticalCoverageBps) return 2;
        if (coverageBps < limit.warningCoverageBps) return 1;
        return 0;
    }

    function _setLimits(Tranche tranche, TrancheLimits memory limits_) internal {
        _validateLimits(limits_);
        uint8 id = _idx(tranche);
        _limits[id] = limits_;
        emit TrancheLimitsUpdated(
            tranche,
            limits_.minDeposit,
            limits_.maxDeposit,
            limits_.maxDailyInflow,
            limits_.maxDailyOutflow,
            limits_.targetWeightBps,
            limits_.warningCoverageBps,
            limits_.criticalCoverageBps,
            limits_.active
        );
    }

    function _validateLimits(TrancheLimits memory limits_) internal pure {
        if (limits_.minDeposit > limits_.maxDeposit) revert Arcadia__ZeroAmount();
        if (limits_.targetWeightBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(limits_.targetWeightBps);
        }
        if (limits_.warningCoverageBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(limits_.warningCoverageBps);
        }
        if (limits_.criticalCoverageBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(limits_.criticalCoverageBps);
        }
        if (limits_.criticalCoverageBps > limits_.warningCoverageBps) {
            revert Arcadia__InvalidBps(limits_.criticalCoverageBps);
        }
    }

    function _rollBucket(uint8 id) internal {
        uint64 day = _currentDay();
        FlowBucket storage bucket = _buckets[id];
        if (bucket.day == day) return;
        uint64 previousDay = bucket.day;
        bucket.day = day;
        bucket.inflow = 0;
        bucket.outflow = 0;
        emit FlowBucketReset(Tranche(id), previousDay, day);
    }

    function _currentDay() internal view returns (uint64) {
        return uint64(block.timestamp / 1 days);
    }

    function _idx(Tranche tranche) internal pure returns (uint8 id) {
        id = uint8(tranche);
        if (id > uint8(Tranche.Junior)) revert Arcadia__InvalidTranche(id);
    }
}
