// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IArcadiaVault } from "../interfaces/IArcadiaVault.sol";
import { Arcadia__ValueOverflow } from "../errors/ArcadiaErrors.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { ProtocolSnapshot, Tranche, TrancheState } from "../types/ArcadiaTypes.sol";

/// @notice Stateless health checks intended for keepers and dashboards.
contract ArcadiaMonitor {
    using FixedPointMath for uint256;

    IArcadiaVault public immutable vault;
    IERC20 public immutable asset;

    constructor(address vault_) {
        vault = IArcadiaVault(vault_);
        asset = IERC20(vault.asset());
    }

    function liquidCoverageBps() public view returns (uint256) {
        ProtocolSnapshot memory snap = vault.snapshot();
        return FixedPointMath.ratioBps(asset.balanceOf(address(vault)), snap.totalAccountedAssets);
    }

    function trancheCoverageBps(Tranche tranche) public view returns (uint256) {
        TrancheState memory state = vault.trancheState(tranche);
        if (tranche == Tranche.Senior) {
            return FixedPointMath.ratioBps(vault.sharedResidualValue(), state.accountedAssets);
        }
        if (tranche == Tranche.Mezzanine) {
            TrancheState memory junior = vault.trancheState(Tranche.Junior);
            return FixedPointMath.ratioBps(junior.accountedAssets, state.accountedAssets);
        }
        return type(uint16).max;
    }

    function pricesSyncedWhenSettled() external view returns (bool) {
        if (vault.openLossReportId() != 0) return true;
        TrancheState memory senior = vault.trancheState(Tranche.Senior);
        TrancheState memory mezzanine = vault.trancheState(Tranche.Mezzanine);
        TrancheState memory junior = vault.trancheState(Tranche.Junior);
        return senior.entryPriceWad == senior.exitPriceWad
            && mezzanine.entryPriceWad == mezzanine.exitPriceWad
            && junior.entryPriceWad == junior.exitPriceWad;
    }

    function canProcessStandardFlow() external view returns (bool) {
        ProtocolSnapshot memory snap = vault.snapshot();
        if (snap.emergencyMode || snap.depositsPaused || snap.redemptionsPaused) return false;
        if (snap.openLossReportId != 0) return true;
        return asset.balanceOf(address(vault)) >= snap.totalAccountedAssets;
    }

    function accountingSurplus() external view returns (int256) {
        ProtocolSnapshot memory snap = vault.snapshot();
        uint256 liquid = asset.balanceOf(address(vault));
        if (liquid >= snap.totalAccountedAssets) {
            return _toInt256(liquid - snap.totalAccountedAssets);
        }
        return -_toInt256(snap.totalAccountedAssets - liquid);
    }

    function _toInt256(uint256 value) internal pure returns (int256) {
        if (value > uint256(type(int256).max)) revert Arcadia__ValueOverflow(value);
        return int256(value);
    }
}
