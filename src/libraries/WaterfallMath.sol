// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaTypes, LossAllocation, HarvestAllocation } from "../types/ArcadiaTypes.sol";
import { FixedPointMath } from "./FixedPointMath.sol";

/// @notice Deterministic tranche waterfall helpers.
library WaterfallMath {
    using FixedPointMath for uint256;

    uint256 internal constant WAD = ArcadiaTypes.WAD;
    uint256 internal constant BPS = ArcadiaTypes.BPS;

    function allocateLoss(
        uint256 lossAmount,
        uint256 juniorAssets,
        uint256 mezzanineAssets,
        uint256 seniorAssets
    ) internal pure returns (LossAllocation memory allocation) {
        uint256 remaining = lossAmount;

        allocation.juniorLoss = remaining.min(juniorAssets);
        remaining -= allocation.juniorLoss;

        allocation.mezzanineLoss = remaining.min(mezzanineAssets);
        remaining -= allocation.mezzanineLoss;

        allocation.seniorLoss = remaining.min(seniorAssets);
        remaining -= allocation.seniorLoss;

        allocation.unallocatedLoss = remaining;
    }

    function allocateHarvest(
        uint256 harvestAmount,
        uint256 seniorAssets,
        uint256 mezzanineAssets,
        uint16 seniorTargetBps,
        uint16 mezzanineTargetBps,
        uint16 protocolFeeBps
    ) internal pure returns (HarvestAllocation memory allocation) {
        allocation.protocolFee = harvestAmount.bpsOf(protocolFeeBps);
        uint256 remaining = harvestAmount - allocation.protocolFee;

        uint256 seniorTarget = seniorAssets.bpsOf(seniorTargetBps);
        allocation.seniorYield = remaining.min(seniorTarget);
        remaining -= allocation.seniorYield;

        uint256 mezzanineTarget = mezzanineAssets.bpsOf(mezzanineTargetBps);
        allocation.mezzanineYield = remaining.min(mezzanineTarget);
        remaining -= allocation.mezzanineYield;

        allocation.juniorYield = remaining;
    }

    function depositShares(uint256 assets, uint256 priceWad) internal pure returns (uint256) {
        return FixedPointMath.sharesForAssets(assets, priceWad);
    }

    function redeemAssets(uint256 shares, uint256 priceWad) internal pure returns (uint256) {
        return FixedPointMath.assetsForShares(shares, priceWad);
    }

    function tranchePrice(uint256 assets, uint256 shares) internal pure returns (uint256) {
        return FixedPointMath.pricePerShare(assets, shares);
    }

    function protectedSeniorPrice(
        uint256 seniorAssets,
        uint256 seniorShares,
        uint256 residualCredit,
        uint16 maxProtectionBps
    ) internal pure returns (uint256) {
        if (seniorShares == 0) return WAD;
        uint256 protectionCap = seniorAssets.bpsOf(maxProtectionBps);
        uint256 protection = residualCredit.min(protectionCap);
        return FixedPointMath.pricePerShare(seniorAssets + protection, seniorShares);
    }

    function protectedMezzaninePrice(
        uint256 mezzanineAssets,
        uint256 mezzanineShares,
        uint256 juniorResidual,
        uint16 maxProtectionBps
    ) internal pure returns (uint256) {
        if (mezzanineShares == 0) return WAD;
        uint256 protectionCap = mezzanineAssets.bpsOf(maxProtectionBps);
        uint256 protection = juniorResidual.min(protectionCap);
        return FixedPointMath.pricePerShare(mezzanineAssets + protection, mezzanineShares);
    }

    function liquidationPrice(uint256 assets, uint256 shares) internal pure returns (uint256) {
        return FixedPointMath.pricePerShare(assets, shares);
    }

    function coverageBps(uint256 seniorAssets, uint256 residualAssets)
        internal
        pure
        returns (uint256)
    {
        if (seniorAssets == 0) return type(uint16).max;
        return FixedPointMath.ratioBps(residualAssets, seniorAssets);
    }

    function totalAssets(uint256 seniorAssets, uint256 mezzanineAssets, uint256 juniorAssets)
        internal
        pure
        returns (uint256)
    {
        return seniorAssets + mezzanineAssets + juniorAssets;
    }
}
