// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Shared constants, enums, and data containers used by Arcadia modules.
library ArcadiaTypes {
    uint256 internal constant WAD = 1e18;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant MAX_FEE_BPS = 1000;
    uint256 internal constant MAX_TRANCHE_BPS = 10_000;
    uint256 internal constant MAX_SYNC_DELAY = 14 days;

    bytes32 internal constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 internal constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 internal constant REPORTER_ROLE = keccak256("REPORTER_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 internal constant STRATEGIST_ROLE = keccak256("STRATEGIST_ROLE");
    bytes32 internal constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");
}

enum Tranche {
    Senior,
    Mezzanine,
    Junior
}

enum LossReportStatus {
    None,
    Pending,
    Settled,
    Cancelled
}

enum StrategyStatus {
    Unlisted,
    Active,
    Paused,
    Retired
}

struct TrancheConfig {
    string name;
    uint16 depositFeeBps;
    uint16 redemptionFeeBps;
    uint16 harvestTargetBps;
    uint16 maxDepositShareBps;
    uint16 minimumCoverageBps;
    bool depositsEnabled;
    bool redemptionsEnabled;
}

struct TrancheState {
    uint256 accountedAssets;
    uint256 lossAbsorbed;
    uint256 yieldAccrued;
    uint256 feesAccrued;
    uint256 entryPriceWad;
    uint256 exitPriceWad;
    uint64 lastPriceUpdate;
}

struct LossAllocation {
    uint256 juniorLoss;
    uint256 mezzanineLoss;
    uint256 seniorLoss;
    uint256 unallocatedLoss;
}

struct HarvestAllocation {
    uint256 seniorYield;
    uint256 mezzanineYield;
    uint256 juniorYield;
    uint256 protocolFee;
}

struct LossReport {
    uint256 id;
    uint256 amount;
    uint256 juniorLoss;
    uint256 mezzanineLoss;
    uint256 seniorLoss;
    uint256 residualBefore;
    uint256 residualAfter;
    uint256 seniorExitPriceWad;
    uint64 reportedAt;
    LossReportStatus status;
    bytes32 reasonHash;
    address reporter;
}

struct HarvestReport {
    uint256 id;
    uint256 amount;
    uint256 seniorYield;
    uint256 mezzanineYield;
    uint256 juniorYield;
    uint256 protocolFee;
    uint64 harvestedAt;
    bytes32 sourceHash;
    address keeper;
}

struct StrategyConfig {
    address strategy;
    uint128 debtLimit;
    uint64 reportDelay;
    uint16 targetDebtBps;
    StrategyStatus status;
}

struct StrategyReport {
    address strategy;
    uint256 totalDebt;
    uint256 estimatedAssets;
    uint256 liquidAssets;
    uint256 pendingGain;
    uint256 pendingLoss;
    uint64 lastReport;
    StrategyStatus status;
}

struct RiskBand {
    uint16 seniorCoverageBps;
    uint16 mezzanineCoverageBps;
    uint16 juniorBufferBps;
    uint16 maxLossReportBps;
    uint64 staleAfter;
    bool active;
}

struct TrancheSnapshot {
    Tranche tranche;
    string name;
    address shareToken;
    uint256 totalShares;
    uint256 accountedAssets;
    uint256 lossAbsorbed;
    uint256 yieldAccrued;
    uint256 entryPriceWad;
    uint256 exitPriceWad;
    uint256 coverageBps;
    bool depositsEnabled;
    bool redemptionsEnabled;
}

struct ProtocolSnapshot {
    uint256 totalAccountedAssets;
    uint256 liquidAssets;
    uint256 sharedResidualValue;
    uint256 totalFeesAccrued;
    uint256 latestHarvestId;
    uint256 latestLossReportId;
    uint256 openLossReportId;
    bool depositsPaused;
    bool redemptionsPaused;
    bool harvestPaused;
    bool emergencyMode;
}
