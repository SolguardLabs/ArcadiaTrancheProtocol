// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Arcadia__InvalidBps, Arcadia__ZeroAmount } from "../errors/ArcadiaErrors.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { WaterfallMath } from "../libraries/WaterfallMath.sol";
import { ArcadiaTypes, LossAllocation } from "../types/ArcadiaTypes.sol";

/// @notice Pure stress engine for tranche solvency and liquidity scenarios.
contract ArcadiaScenarioEngine {
    using FixedPointMath for uint256;

    enum RiskTier {
        Core,
        Standard,
        Elevated,
        Restricted
    }

    struct Portfolio {
        uint256 seniorAssets;
        uint256 mezzanineAssets;
        uint256 juniorAssets;
        uint256 liquidAssets;
    }

    struct Shock {
        uint16 lossBps;
        uint16 liquidityHaircutBps;
        uint16 correlationBps;
        uint16 concentrationBps;
        uint16 minimumLiquidBufferBps;
    }

    struct ScenarioResult {
        uint256 grossLoss;
        uint256 juniorLoss;
        uint256 mezzanineLoss;
        uint256 seniorLoss;
        uint256 postSeniorAssets;
        uint256 postMezzanineAssets;
        uint256 postJuniorAssets;
        uint256 stressedLiquidity;
        uint256 requiredLiquidity;
        uint256 liquidityShortfall;
        uint256 seniorCoverageBps;
        uint256 riskScoreBps;
        RiskTier tier;
        bool solvent;
        bytes32 scenarioDigest;
    }

    function assess(Portfolio calldata portfolio, Shock calldata shock)
        external
        pure
        returns (ScenarioResult memory result)
    {
        _validateShock(shock);
        uint256 total = portfolio.seniorAssets + portfolio.mezzanineAssets + portfolio.juniorAssets;
        if (total == 0) revert Arcadia__ZeroAmount();

        result.grossLoss = total.bpsOf(shock.lossBps);
        LossAllocation memory allocation = WaterfallMath.allocateLoss(
            result.grossLoss,
            portfolio.juniorAssets,
            portfolio.mezzanineAssets,
            portfolio.seniorAssets
        );
        result.juniorLoss = allocation.juniorLoss;
        result.mezzanineLoss = allocation.mezzanineLoss;
        result.seniorLoss = allocation.seniorLoss;
        result.postSeniorAssets = portfolio.seniorAssets - allocation.seniorLoss;
        result.postMezzanineAssets = portfolio.mezzanineAssets - allocation.mezzanineLoss;
        result.postJuniorAssets = portfolio.juniorAssets - allocation.juniorLoss;

        result.stressedLiquidity =
            portfolio.liquidAssets.bpsOf(ArcadiaTypes.BPS - shock.liquidityHaircutBps);
        uint256 postTotal =
            result.postSeniorAssets + result.postMezzanineAssets + result.postJuniorAssets;
        result.requiredLiquidity = postTotal.bpsOf(shock.minimumLiquidBufferBps);
        result.liquidityShortfall = result.requiredLiquidity.zeroFloorSub(result.stressedLiquidity);
        uint256 subordinated = result.postMezzanineAssets + result.postJuniorAssets;
        result.seniorCoverageBps = result.postSeniorAssets == 0
            ? type(uint16).max
            : FixedPointMath.ratioBps(subordinated, result.postSeniorAssets);

        result.riskScoreBps =
            (uint256(shock.lossBps)
                    * 3500
                    + uint256(shock.liquidityHaircutBps)
                    * 2500
                    + uint256(shock.correlationBps)
                    * 2000
                    + uint256(shock.concentrationBps)
                    * 2000) / ArcadiaTypes.BPS;
        result.tier = _tier(result.riskScoreBps, allocation.seniorLoss);
        result.solvent = allocation.unallocatedLoss == 0 && result.liquidityShortfall == 0;
        result.scenarioDigest = keccak256(
            abi.encode(
                "ARCADIA_SCENARIO_V1",
                portfolio,
                shock,
                result.grossLoss,
                allocation,
                result.stressedLiquidity,
                result.requiredLiquidity,
                result.riskScoreBps
            )
        );
    }

    function _validateShock(Shock calldata shock) internal pure {
        uint16[5] memory values = [
            shock.lossBps,
            shock.liquidityHaircutBps,
            shock.correlationBps,
            shock.concentrationBps,
            shock.minimumLiquidBufferBps
        ];
        for (uint256 i; i < values.length; ++i) {
            if (values[i] > ArcadiaTypes.BPS) revert Arcadia__InvalidBps(values[i]);
        }
    }

    function _tier(uint256 scoreBps, uint256 seniorLoss) internal pure returns (RiskTier) {
        if (seniorLoss != 0 || scoreBps >= 7000) return RiskTier.Restricted;
        if (scoreBps >= 4500) return RiskTier.Elevated;
        if (scoreBps >= 2000) return RiskTier.Standard;
        return RiskTier.Core;
    }
}
