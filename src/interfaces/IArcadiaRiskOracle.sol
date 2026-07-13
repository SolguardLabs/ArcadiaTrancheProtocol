// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { RiskBand, Tranche } from "../types/ArcadiaTypes.sol";

interface IArcadiaRiskOracle {
    event RiskBandUpdated(
        Tranche indexed tranche,
        uint16 seniorCoverageBps,
        uint16 mezzanineCoverageBps,
        uint16 juniorBufferBps,
        uint16 maxLossReportBps,
        uint64 staleAfter
    );
    event PriceObservationUpdated(
        bytes32 indexed marketId, uint256 confidenceBps, uint64 observedAt
    );

    function riskBand(Tranche tranche) external view returns (RiskBand memory);
    function requireActiveBand(Tranche tranche) external view returns (RiskBand memory);
    function maxLossReport(uint256 totalAssets, Tranche tranche) external view returns (uint256);
    function coverageHealthy(Tranche tranche, uint256 seniorAssets, uint256 residualAssets)
        external
        view
        returns (bool);
}
