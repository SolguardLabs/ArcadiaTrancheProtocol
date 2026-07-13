// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";
import { IArcadiaLens } from "../interfaces/IArcadiaLens.sol";
import { IArcadiaVault } from "../interfaces/IArcadiaVault.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import {
    ProtocolSnapshot,
    Tranche,
    TrancheConfig,
    TrancheSnapshot,
    TrancheState
} from "../types/ArcadiaTypes.sol";

/// @notice Aggregated read model for interfaces and monitoring jobs.
contract ArcadiaLens is IArcadiaLens {
    using FixedPointMath for uint256;

    IArcadiaVault public immutable vault;

    constructor(address vault_) {
        vault = IArcadiaVault(vault_);
    }

    function protocolSnapshot() external view override returns (ProtocolSnapshot memory) {
        return vault.snapshot();
    }

    function trancheSnapshot(Tranche tranche)
        public
        view
        override
        returns (TrancheSnapshot memory snapshot)
    {
        TrancheConfig memory config = vault.trancheConfig(tranche);
        TrancheState memory state = vault.trancheState(tranche);
        address token = vault.trancheShareToken(tranche);
        uint256 shares = IERC20(token).totalSupply();
        uint256 residual = vault.sharedResidualValue();
        uint256 coverage;

        if (tranche == Tranche.Senior) {
            coverage = FixedPointMath.ratioBps(residual, state.accountedAssets);
        } else if (tranche == Tranche.Mezzanine) {
            TrancheState memory junior = vault.trancheState(Tranche.Junior);
            coverage = FixedPointMath.ratioBps(junior.accountedAssets, state.accountedAssets);
        } else {
            coverage = 0;
        }

        snapshot = TrancheSnapshot({
            tranche: tranche,
            name: config.name,
            shareToken: token,
            totalShares: shares,
            accountedAssets: state.accountedAssets,
            lossAbsorbed: state.lossAbsorbed,
            yieldAccrued: state.yieldAccrued,
            entryPriceWad: state.entryPriceWad,
            exitPriceWad: state.exitPriceWad,
            coverageBps: coverage,
            depositsEnabled: config.depositsEnabled,
            redemptionsEnabled: config.redemptionsEnabled
        });
    }

    function allTranches() external view override returns (TrancheSnapshot[3] memory snapshots) {
        snapshots[0] = trancheSnapshot(Tranche.Senior);
        snapshots[1] = trancheSnapshot(Tranche.Mezzanine);
        snapshots[2] = trancheSnapshot(Tranche.Junior);
    }

    function accountValue(address account) external view override returns (uint256 value) {
        value += _accountTrancheValue(account, Tranche.Senior);
        value += _accountTrancheValue(account, Tranche.Mezzanine);
        value += _accountTrancheValue(account, Tranche.Junior);
    }

    function _accountTrancheValue(address account, Tranche tranche)
        internal
        view
        returns (uint256)
    {
        address token = vault.trancheShareToken(tranche);
        uint256 shares = IERC20(token).balanceOf(account);
        if (shares == 0) return 0;
        TrancheState memory state = vault.trancheState(tranche);
        return FixedPointMath.assetsForShares(shares, state.exitPriceWad);
    }
}
