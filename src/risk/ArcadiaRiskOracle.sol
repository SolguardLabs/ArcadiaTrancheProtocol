// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__InvalidBps,
    Arcadia__RiskBandInactive,
    Arcadia__StrategyReportStale,
    Arcadia__ZeroAddress
} from "../errors/ArcadiaErrors.sol";
import { IArcadiaRiskOracle } from "../interfaces/IArcadiaRiskOracle.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ArcadiaTypes, RiskBand, Tranche } from "../types/ArcadiaTypes.sol";

/// @notice Risk parameter registry for tranche coverage checks and loss report bounds.
contract ArcadiaRiskOracle is ArcadiaRoles, IArcadiaRiskOracle {
    using FixedPointMath for uint256;

    struct PriceObservation {
        uint256 confidenceBps;
        uint64 observedAt;
        bytes32 dataHash;
    }

    mapping(uint8 => RiskBand) private _bands;
    mapping(bytes32 => PriceObservation) public observations;

    event ObservationDataHashUpdated(bytes32 indexed marketId, bytes32 indexed dataHash);

    constructor(address admin) ArcadiaRoles(admin) {
        _grantInitialRole(ArcadiaTypes.RISK_MANAGER_ROLE, admin);
        _setBand(Tranche.Senior, RiskBand(3000, 0, 0, 1500, 1 days, true));
        _setBand(Tranche.Mezzanine, RiskBand(0, 1500, 0, 2500, 1 days, true));
        _setBand(Tranche.Junior, RiskBand(0, 0, 0, 10_000, 1 days, true));
    }

    function setRiskBand(Tranche tranche, RiskBand calldata band)
        external
        onlyRole(ArcadiaTypes.RISK_MANAGER_ROLE)
    {
        _validateBand(band);
        _setBand(tranche, band);
    }

    function riskBand(Tranche tranche) external view override returns (RiskBand memory) {
        return _bands[uint8(tranche)];
    }

    function requireActiveBand(Tranche tranche)
        public
        view
        override
        returns (RiskBand memory band)
    {
        band = _bands[uint8(tranche)];
        if (!band.active) revert Arcadia__RiskBandInactive(uint8(tranche));
    }

    function setPriceObservation(bytes32 marketId, uint256 confidenceBps, bytes32 dataHash)
        external
        onlyRole(ArcadiaTypes.RISK_MANAGER_ROLE)
    {
        if (marketId == bytes32(0)) revert Arcadia__ZeroAddress();
        if (confidenceBps > ArcadiaTypes.BPS) revert Arcadia__InvalidBps(confidenceBps);
        observations[marketId] = PriceObservation({
            confidenceBps: confidenceBps, observedAt: uint64(block.timestamp), dataHash: dataHash
        });
        emit PriceObservationUpdated(marketId, confidenceBps, uint64(block.timestamp));
        emit ObservationDataHashUpdated(marketId, dataHash);
    }

    function requireFreshObservation(bytes32 marketId, uint64 staleAfter)
        external
        view
        returns (PriceObservation memory observation)
    {
        observation = observations[marketId];
        if (block.timestamp > uint256(observation.observedAt) + staleAfter) {
            revert Arcadia__StrategyReportStale(address(0), observation.observedAt, staleAfter);
        }
    }

    function maxLossReport(uint256 totalAssets, Tranche tranche)
        external
        view
        override
        returns (uint256)
    {
        RiskBand memory band = requireActiveBand(tranche);
        return totalAssets.bpsOf(band.maxLossReportBps);
    }

    function coverageHealthy(Tranche tranche, uint256 seniorAssets, uint256 residualAssets)
        external
        view
        override
        returns (bool)
    {
        RiskBand memory band = requireActiveBand(tranche);
        if (tranche == Tranche.Senior) {
            return FixedPointMath.ratioBps(residualAssets, seniorAssets) >= band.seniorCoverageBps;
        }
        if (tranche == Tranche.Mezzanine) {
            return
                FixedPointMath.ratioBps(residualAssets, seniorAssets) >= band.mezzanineCoverageBps;
        }
        return true;
    }

    function _setBand(Tranche tranche, RiskBand memory band) internal {
        _validateBand(band);
        _bands[uint8(tranche)] = band;
        emit RiskBandUpdated(
            tranche,
            band.seniorCoverageBps,
            band.mezzanineCoverageBps,
            band.juniorBufferBps,
            band.maxLossReportBps,
            band.staleAfter
        );
    }

    function _validateBand(RiskBand memory band) internal pure {
        if (band.seniorCoverageBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(band.seniorCoverageBps);
        }
        if (band.mezzanineCoverageBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(band.mezzanineCoverageBps);
        }
        if (band.juniorBufferBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(band.juniorBufferBps);
        }
        if (band.maxLossReportBps > ArcadiaTypes.BPS) {
            revert Arcadia__InvalidBps(band.maxLossReportBps);
        }
    }
}
