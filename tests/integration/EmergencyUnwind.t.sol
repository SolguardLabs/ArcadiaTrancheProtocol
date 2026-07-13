// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaFixture } from "../helpers/ArcadiaFixture.sol";
import { LossReportStatus, Tranche } from "../../src/types/ArcadiaTypes.sol";

contract EmergencyUnwindTest is ArcadiaFixture {
    function test_emergencyModeSettlesOpenReportAndUsesLiquidationPrice() public {
        _seedBalancedVault();
        uint256 reportId = _reportLoss(300 ether);

        vm.prank(GUARDIAN);
        vault.enterEmergencyMode();

        assertTrue(vault.emergencyMode());
        assertEq(vault.openLossReportId(), 0);
        assertEq(uint8(vault.lossReport(reportId).status), uint8(LossReportStatus.Settled));

        uint256 carolBefore = asset.balanceOf(CAROL);
        vm.prank(CAROL);
        uint256 assetsOut = vault.emergencyRedeem(Tranche.Junior, 250 ether, CAROL, CAROL);

        assertEq(assetsOut, 100 ether);
        assertEq(asset.balanceOf(CAROL), carolBefore + 100 ether);
        assertEq(_share(Tranche.Junior).balanceOf(CAROL), 250 ether);
        assertEq(_state(Tranche.Junior).accountedAssets, 100 ether);
        _assertSettledAccounting();
    }

    function test_standardDepositIsUnavailableDuringEmergency() public {
        _seedBalancedVault();

        vm.prank(GUARDIAN);
        vault.enterEmergencyMode();

        vm.expectRevert();
        vm.prank(ALICE);
        vault.deposit(Tranche.Senior, 1 ether, ALICE);
    }
}
