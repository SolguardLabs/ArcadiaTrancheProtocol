// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import {
    Arcadia__StrategyReportStale,
    Arcadia__Unauthorized
} from "../../src/errors/ArcadiaErrors.sol";
import { ArcadiaTimelock } from "../../src/governance/ArcadiaTimelock.sol";
import { StrategyConfig, StrategyReport, StrategyStatus } from "../../src/types/ArcadiaTypes.sol";
import { ArcadiaStrategyRegistry } from "../../src/vault/ArcadiaStrategyRegistry.sol";

contract GovernanceAndRegistryTest is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant VAULT = address(0xA11CA);
    address internal constant STRATEGY = address(0x57A7E);

    function test_timelockRequiresPredecessorAndSelfAdministersDelay() public {
        ArcadiaTimelock timelock = new ArcadiaTimelock(ADMIN, 2 days, 7 days);
        bytes memory firstCall = abi.encodeCall(ArcadiaTimelock.updateGracePeriod, (8 days));
        bytes32 firstSalt = keccak256("risk-committee-44");

        vm.prank(ADMIN);
        bytes32 firstId =
            timelock.schedule(address(timelock), 0, firstCall, bytes32(0), firstSalt, 1 days);

        bytes memory secondCall = abi.encodeCall(ArcadiaTimelock.updateDelay, (3 days));
        vm.prank(ADMIN);
        bytes32 secondId = timelock.schedule(
            address(timelock), 0, secondCall, firstId, keccak256("risk-committee-45"), 2 days
        );

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                Arcadia__Unauthorized.selector, bytes32("PREDECESSOR"), address(this)
            )
        );
        timelock.execute(secondId);

        timelock.execute(firstId);
        timelock.execute(secondId);
        assertEq(timelock.gracePeriod(), 8 days);
        assertEq(timelock.minDelay(), 3 days);
    }

    function test_strategyRegistryAccountsFreshReportsAndTargetDebtGap() public {
        ArcadiaStrategyRegistry registry = new ArcadiaStrategyRegistry(ADMIN, VAULT);
        StrategyConfig memory config = StrategyConfig({
            strategy: STRATEGY,
            debtLimit: 1000 ether,
            reportDelay: 1 days,
            targetDebtBps: 4000,
            status: StrategyStatus.Active
        });
        vm.prank(ADMIN);
        registry.addStrategy(config);

        StrategyReport memory report = StrategyReport({
            strategy: STRATEGY,
            totalDebt: 300 ether,
            estimatedAssets: 320 ether,
            liquidAssets: 80 ether,
            pendingGain: 20 ether,
            pendingLoss: 0,
            lastReport: uint64(block.timestamp),
            status: StrategyStatus.Active
        });
        vm.prank(ADMIN);
        registry.recordManualReport(report);

        assertEq(registry.totalDebt(), 300 ether);
        assertEq(registry.totalEstimatedAssets(), 320 ether);
        assertEq(registry.targetDebtGap(STRATEGY, 1000 ether), 100 ether);
        assertEq(registry.requireFreshReport(STRATEGY).liquidAssets, 80 ether);

        vm.warp(block.timestamp + 1 days + 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Arcadia__StrategyReportStale.selector,
                STRATEGY,
                report.lastReport,
                config.reportDelay
            )
        );
        registry.requireFreshReport(STRATEGY);
    }

    function test_strategyRegistryRejectsUninitializedManualReport() public {
        ArcadiaStrategyRegistry registry = new ArcadiaStrategyRegistry(ADMIN, VAULT);
        vm.prank(ADMIN);
        registry.addStrategy(
            StrategyConfig({
                strategy: STRATEGY,
                debtLimit: 1000 ether,
                reportDelay: 1 days,
                targetDebtBps: 4000,
                status: StrategyStatus.Active
            })
        );

        vm.expectRevert(
            abi.encodeWithSelector(Arcadia__StrategyReportStale.selector, STRATEGY, 0, 1 days)
        );
        vm.prank(ADMIN);
        registry.recordManualReport(
            StrategyReport({
                strategy: STRATEGY,
                totalDebt: 0,
                estimatedAssets: 0,
                liquidAssets: 0,
                pendingGain: 0,
                pendingLoss: 0,
                lastReport: 0,
                status: StrategyStatus.Active
            })
        );
    }
}
