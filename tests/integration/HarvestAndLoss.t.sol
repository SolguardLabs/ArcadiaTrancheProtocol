// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaFixture } from "../helpers/ArcadiaFixture.sol";
import {
    LossReport,
    LossReportStatus,
    Tranche,
    TrancheState
} from "../../src/types/ArcadiaTypes.sol";

contract HarvestAndLossTest is ArcadiaFixture {
    function test_harvestDistributesTargetYieldAndResidual() public {
        _seedBalancedVault();

        uint256 harvestId = _harvest(150 ether);

        TrancheState memory senior = _state(Tranche.Senior);
        TrancheState memory mezzanine = _state(Tranche.Mezzanine);
        TrancheState memory junior = _state(Tranche.Junior);

        assertEq(harvestId, 1);
        assertEq(senior.yieldAccrued, 40 ether);
        assertEq(mezzanine.yieldAccrued, 45 ether);
        assertEq(junior.yieldAccrued, 65 ether);
        assertEq(senior.accountedAssets, 1040 ether);
        assertEq(mezzanine.accountedAssets, 545 ether);
        assertEq(junior.accountedAssets, 565 ether);
        assertEq(vault.totalAccountedAssets(), 2150 ether);
        assertEq(vault.sharedResidualValue(), 1110 ether);
        _assertSettledAccounting();
    }

    function test_lossReportAllocatesJuniorFirstAndSettlesResiduals() public {
        _seedBalancedVault();
        _harvest(150 ether);

        uint256 reportId = _reportLoss(300 ether);
        LossReport memory report = vault.lossReport(reportId);

        assertEq(report.id, 1);
        assertEq(uint8(report.status), uint8(LossReportStatus.Pending));
        assertEq(report.juniorLoss, 300 ether);
        assertEq(report.mezzanineLoss, 0);
        assertEq(report.seniorLoss, 0);
        assertEq(report.residualBefore, 1110 ether);
        assertEq(report.residualAfter, 810 ether);
        assertEq(vault.openLossReportId(), reportId);
        assertEq(asset.balanceOf(LOSS_RECEIVER), 300 ether);
        assertEq(_state(Tranche.Junior).accountedAssets, 265 ether);
        assertEq(vault.totalAccountedAssets(), 1850 ether);

        _settle(reportId);
        LossReport memory settled = vault.lossReport(reportId);
        assertEq(uint8(settled.status), uint8(LossReportStatus.Settled));
        assertEq(vault.openLossReportId(), 0);
        assertEq(vault.sharedResidualValue(), 810 ether);
        _assertSettledAccounting();
    }

    function test_lossWaterfallReachesMezzanineAfterJuniorBuffer() public {
        _seedBalancedVault();

        uint256 reportId = _reportLoss(700 ether);
        LossReport memory report = vault.lossReport(reportId);

        assertEq(report.juniorLoss, 500 ether);
        assertEq(report.mezzanineLoss, 200 ether);
        assertEq(report.seniorLoss, 0);
        assertEq(_state(Tranche.Junior).accountedAssets, 0);
        assertEq(_state(Tranche.Mezzanine).accountedAssets, 300 ether);
        assertEq(_state(Tranche.Senior).accountedAssets, 1000 ether);

        _settle(reportId);
        assertEq(vault.sharedResidualValue(), 300 ether);
    }
}
