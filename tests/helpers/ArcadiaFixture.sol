// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { ArcadiaTrancheVault } from "../../src/vault/ArcadiaTrancheVault.sol";
import { ArcadiaLens } from "../../src/views/ArcadiaLens.sol";
import { ArcadiaMonitor } from "../../src/views/ArcadiaMonitor.sol";
import { MockERC20 } from "../../src/mocks/MockERC20.sol";
import { TrancheShareToken } from "../../src/token/TrancheShareToken.sol";
import {
    ArcadiaTypes,
    ProtocolSnapshot,
    Tranche,
    TrancheState
} from "../../src/types/ArcadiaTypes.sol";

abstract contract ArcadiaFixture is Test {
    address internal constant ADMIN = address(0xA11CE);
    address internal constant KEEPER = address(0xBEEF);
    address internal constant REPORTER = address(0xCAFE);
    address internal constant GUARDIAN = address(0x600D);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant LOSS_RECEIVER = address(0x1055);
    address internal constant ALICE = address(0xA1);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA401);

    uint256 internal constant USER_BALANCE = 10_000_000 ether;
    uint256 internal constant KEEPER_BALANCE = 2_000_000 ether;

    MockERC20 internal asset;
    ArcadiaTrancheVault internal vault;
    ArcadiaLens internal lens;
    ArcadiaMonitor internal monitor;

    function setUp() public virtual {
        vm.label(ADMIN, "Admin");
        vm.label(KEEPER, "Keeper");
        vm.label(REPORTER, "Reporter");
        vm.label(GUARDIAN, "Guardian");
        vm.label(TREASURY, "Treasury");
        vm.label(LOSS_RECEIVER, "Loss receiver");
        vm.label(ALICE, "Alice");
        vm.label(BOB, "Bob");
        vm.label(CAROL, "Carol");

        asset = new MockERC20("Arcadia USD", "aUSD", 18, ADMIN, 0);

        vm.startPrank(ADMIN);
        vault = new ArcadiaTrancheVault(address(asset), ADMIN, TREASURY, LOSS_RECEIVER);
        vault.grantRole(ArcadiaTypes.KEEPER_ROLE, KEEPER);
        vault.grantRole(ArcadiaTypes.REPORTER_ROLE, REPORTER);
        vault.grantRole(ArcadiaTypes.GUARDIAN_ROLE, GUARDIAN);
        asset.mint(ALICE, USER_BALANCE);
        asset.mint(BOB, USER_BALANCE);
        asset.mint(CAROL, USER_BALANCE);
        asset.mint(KEEPER, KEEPER_BALANCE);
        vm.stopPrank();

        lens = new ArcadiaLens(address(vault));
        monitor = new ArcadiaMonitor(address(vault));

        _approve(ALICE);
        _approve(BOB);
        _approve(CAROL);
        _approve(KEEPER);
    }

    function _approve(address account) internal {
        vm.prank(account);
        asset.approve(address(vault), type(uint256).max);
    }

    function _deposit(address account, Tranche tranche, uint256 assets)
        internal
        returns (uint256 shares)
    {
        vm.prank(account);
        shares = vault.deposit(tranche, assets, account);
    }

    function _redeem(address account, Tranche tranche, uint256 shares)
        internal
        returns (uint256 assetsOut)
    {
        vm.prank(account);
        assetsOut = vault.redeem(tranche, shares, account, account);
    }

    function _harvest(uint256 amount) internal returns (uint256 harvestId) {
        vm.prank(KEEPER);
        harvestId = vault.harvest(amount, keccak256("realized-yield"));
    }

    function _reportLoss(uint256 amount) internal returns (uint256 reportId) {
        vm.prank(REPORTER);
        reportId = vault.reportLoss(amount, keccak256("strategy-loss"));
    }

    function _settle(uint256 reportId) internal {
        vm.prank(KEEPER);
        vault.settleLossReport(reportId);
    }

    function _share(Tranche tranche) internal view returns (TrancheShareToken) {
        return TrancheShareToken(vault.trancheShareToken(tranche));
    }

    function _state(Tranche tranche) internal view returns (TrancheState memory) {
        return vault.trancheState(tranche);
    }

    function _seedBalancedVault() internal {
        _deposit(ALICE, Tranche.Senior, 1000 ether);
        _deposit(BOB, Tranche.Mezzanine, 500 ether);
        _deposit(CAROL, Tranche.Junior, 500 ether);
    }

    function _assertSettledAccounting() internal {
        ProtocolSnapshot memory snap = vault.snapshot();
        TrancheState memory senior = vault.trancheState(Tranche.Senior);
        TrancheState memory mezzanine = vault.trancheState(Tranche.Mezzanine);
        TrancheState memory junior = vault.trancheState(Tranche.Junior);

        assertEq(
            snap.totalAccountedAssets,
            senior.accountedAssets + mezzanine.accountedAssets + junior.accountedAssets
        );
        if (snap.openLossReportId == 0) {
            assertEq(snap.sharedResidualValue, mezzanine.accountedAssets + junior.accountedAssets);
        }
    }
}
