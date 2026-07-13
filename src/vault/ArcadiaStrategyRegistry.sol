// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__InvalidBps,
    Arcadia__InvalidStrategy,
    Arcadia__StrategyAlreadyListed,
    Arcadia__StrategyDebtLimitExceeded,
    Arcadia__StrategyNotActive,
    Arcadia__StrategyReportStale,
    Arcadia__ZeroAddress
} from "../errors/ArcadiaErrors.sol";
import { IArcadiaStrategy } from "../interfaces/IArcadiaStrategy.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import {
    ArcadiaTypes,
    StrategyConfig,
    StrategyReport,
    StrategyStatus
} from "../types/ArcadiaTypes.sol";

/// @notice Registry for strategy debt limits, reports, and allocation targets.
contract ArcadiaStrategyRegistry is ArcadiaRoles {
    using FixedPointMath for uint256;

    address public immutable vault;
    uint256 public totalDebt;
    uint256 public totalEstimatedAssets;
    uint256 public totalLiquidAssets;
    uint256 public totalPendingGain;
    uint256 public totalPendingLoss;

    address[] private _strategies;
    mapping(address => StrategyConfig) private _configs;
    mapping(address => StrategyReport) private _reports;
    mapping(address => bool) private _listed;
    mapping(address => uint256) private _indexOf;

    event StrategyAdded(
        address indexed strategy,
        uint256 indexed index,
        uint128 debtLimit,
        uint64 reportDelay,
        uint16 targetDebtBps
    );
    event StrategyConfigUpdated(
        address indexed strategy,
        uint128 debtLimit,
        uint64 reportDelay,
        uint16 targetDebtBps,
        StrategyStatus status
    );
    event StrategyRemoved(address indexed strategy);
    event StrategyReportRecorded(
        address indexed strategy,
        uint256 totalDebt,
        uint256 estimatedAssets,
        uint256 liquidAssets,
        uint256 pendingGain,
        uint256 pendingLoss
    );
    event AggregateReportUpdated(
        uint256 totalDebt,
        uint256 totalEstimatedAssets,
        uint256 totalLiquidAssets,
        uint256 totalPendingGain,
        uint256 totalPendingLoss
    );

    constructor(address admin, address vault_) ArcadiaRoles(admin) {
        if (vault_ == address(0)) revert Arcadia__ZeroAddress();
        vault = vault_;
        _grantInitialRole(ArcadiaTypes.STRATEGIST_ROLE, admin);
        _grantInitialRole(ArcadiaTypes.KEEPER_ROLE, admin);
    }

    function addStrategy(StrategyConfig calldata config)
        external
        onlyRole(ArcadiaTypes.STRATEGIST_ROLE)
    {
        _validateConfig(config);
        address strategy = config.strategy;
        if (_listed[strategy]) revert Arcadia__StrategyAlreadyListed(strategy);

        _listed[strategy] = true;
        _indexOf[strategy] = _strategies.length;
        _strategies.push(strategy);
        _configs[strategy] = config;

        emit StrategyAdded(
            strategy,
            _strategies.length - 1,
            config.debtLimit,
            config.reportDelay,
            config.targetDebtBps
        );
    }

    function updateStrategy(StrategyConfig calldata config)
        external
        onlyRole(ArcadiaTypes.STRATEGIST_ROLE)
    {
        _validateListed(config.strategy);
        _validateConfig(config);
        _configs[config.strategy] = config;
        emit StrategyConfigUpdated(
            config.strategy,
            config.debtLimit,
            config.reportDelay,
            config.targetDebtBps,
            config.status
        );
    }

    function setStrategyStatus(address strategy, StrategyStatus status)
        external
        onlyRole(ArcadiaTypes.STRATEGIST_ROLE)
    {
        _validateListed(strategy);
        StrategyConfig storage config = _configs[strategy];
        config.status = status;
        emit StrategyConfigUpdated(
            strategy, config.debtLimit, config.reportDelay, config.targetDebtBps, config.status
        );
    }

    function removeStrategy(address strategy) external onlyRole(ArcadiaTypes.STRATEGIST_ROLE) {
        _validateListed(strategy);
        StrategyReport memory report = _reports[strategy];
        if (report.totalDebt != 0) {
            revert Arcadia__StrategyDebtLimitExceeded(strategy, report.totalDebt, 0);
        }

        uint256 index = _indexOf[strategy];
        uint256 lastIndex = _strategies.length - 1;
        if (index != lastIndex) {
            address moved = _strategies[lastIndex];
            _strategies[index] = moved;
            _indexOf[moved] = index;
        }
        _strategies.pop();

        delete _listed[strategy];
        delete _indexOf[strategy];
        delete _configs[strategy];
        delete _reports[strategy];

        _recomputeAggregates();
        emit StrategyRemoved(strategy);
    }

    function recordReport(address strategy) external onlyRole(ArcadiaTypes.KEEPER_ROLE) {
        _validateListed(strategy);
        StrategyConfig memory config = _configs[strategy];
        if (config.status != StrategyStatus.Active) revert Arcadia__StrategyNotActive(strategy);

        StrategyReport memory report = IArcadiaStrategy(strategy).report();
        if (report.strategy != strategy) revert Arcadia__InvalidStrategy(strategy);
        if (report.totalDebt > config.debtLimit) {
            revert Arcadia__StrategyDebtLimitExceeded(strategy, report.totalDebt, config.debtLimit);
        }

        _reports[strategy] = report;
        _recomputeAggregates();

        emit StrategyReportRecorded(
            strategy,
            report.totalDebt,
            report.estimatedAssets,
            report.liquidAssets,
            report.pendingGain,
            report.pendingLoss
        );
    }

    function recordManualReport(StrategyReport calldata report)
        external
        onlyRole(ArcadiaTypes.KEEPER_ROLE)
    {
        _validateListed(report.strategy);
        StrategyConfig memory config = _configs[report.strategy];
        if (report.totalDebt > config.debtLimit) {
            revert Arcadia__StrategyDebtLimitExceeded(
                report.strategy, report.totalDebt, config.debtLimit
            );
        }
        _reports[report.strategy] = report;
        _recomputeAggregates();
        emit StrategyReportRecorded(
            report.strategy,
            report.totalDebt,
            report.estimatedAssets,
            report.liquidAssets,
            report.pendingGain,
            report.pendingLoss
        );
    }

    function requireFreshReport(address strategy)
        external
        view
        returns (StrategyReport memory report)
    {
        _validateListed(strategy);
        StrategyConfig memory config = _configs[strategy];
        report = _reports[strategy];
        if (block.timestamp > uint256(report.lastReport) + config.reportDelay) {
            revert Arcadia__StrategyReportStale(strategy, report.lastReport, config.reportDelay);
        }
    }

    function strategyCount() external view returns (uint256) {
        return _strategies.length;
    }

    function strategyAt(uint256 index) external view returns (address) {
        return _strategies[index];
    }

    function isListed(address strategy) external view returns (bool) {
        return _listed[strategy];
    }

    function configOf(address strategy) external view returns (StrategyConfig memory) {
        _validateListed(strategy);
        return _configs[strategy];
    }

    function reportOf(address strategy) external view returns (StrategyReport memory) {
        _validateListed(strategy);
        return _reports[strategy];
    }

    function activeDebtBps(address strategy) external view returns (uint256) {
        _validateListed(strategy);
        if (totalDebt == 0) return 0;
        return FixedPointMath.ratioBps(_reports[strategy].totalDebt, totalDebt);
    }

    function targetDebtGap(address strategy, uint256 vaultAssets)
        external
        view
        returns (int256 gap)
    {
        _validateListed(strategy);
        StrategyConfig memory config = _configs[strategy];
        uint256 targetDebt = vaultAssets.bpsOf(config.targetDebtBps);
        uint256 currentDebt = _reports[strategy].totalDebt;
        if (targetDebt >= currentDebt) return int256(targetDebt - currentDebt);
        return -int256(currentDebt - targetDebt);
    }

    function aggregateReport() external view returns (StrategyReport memory report) {
        report = StrategyReport({
            strategy: address(this),
            totalDebt: totalDebt,
            estimatedAssets: totalEstimatedAssets,
            liquidAssets: totalLiquidAssets,
            pendingGain: totalPendingGain,
            pendingLoss: totalPendingLoss,
            lastReport: uint64(block.timestamp),
            status: StrategyStatus.Active
        });
    }

    function _validateConfig(StrategyConfig calldata config) internal pure {
        if (config.strategy == address(0)) revert Arcadia__ZeroAddress();
        if (config.targetDebtBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(config.targetDebtBps);
        }
    }

    function _validateListed(address strategy) internal view {
        if (!_listed[strategy]) revert Arcadia__InvalidStrategy(strategy);
    }

    function _recomputeAggregates() internal {
        uint256 debt;
        uint256 estimated;
        uint256 liquid;
        uint256 gain;
        uint256 loss;

        for (uint256 i; i < _strategies.length; ++i) {
            StrategyReport memory report = _reports[_strategies[i]];
            debt += report.totalDebt;
            estimated += report.estimatedAssets;
            liquid += report.liquidAssets;
            gain += report.pendingGain;
            loss += report.pendingLoss;
        }

        totalDebt = debt;
        totalEstimatedAssets = estimated;
        totalLiquidAssets = liquid;
        totalPendingGain = gain;
        totalPendingLoss = loss;

        emit AggregateReportUpdated(debt, estimated, liquid, gain, loss);
    }
}
