// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaFixture } from "../helpers/ArcadiaFixture.sol";
import { Tranche, TrancheState } from "../../src/types/ArcadiaTypes.sol";

contract DepositsTest is ArcadiaFixture {
    function test_depositsMintSharesForEveryTranche() public {
        uint256 seniorShares = _deposit(ALICE, Tranche.Senior, 1000 ether);
        uint256 mezzanineShares = _deposit(BOB, Tranche.Mezzanine, 500 ether);
        uint256 juniorShares = _deposit(CAROL, Tranche.Junior, 500 ether);

        assertEq(seniorShares, 1000 ether);
        assertEq(mezzanineShares, 500 ether);
        assertEq(juniorShares, 500 ether);
        assertEq(_share(Tranche.Senior).balanceOf(ALICE), 1000 ether);
        assertEq(_share(Tranche.Mezzanine).balanceOf(BOB), 500 ether);
        assertEq(_share(Tranche.Junior).balanceOf(CAROL), 500 ether);
        assertEq(asset.balanceOf(address(vault)), 2000 ether);
        assertEq(vault.totalAccountedAssets(), 2000 ether);
        assertEq(vault.sharedResidualValue(), 1000 ether);
        _assertSettledAccounting();
    }

    function test_depositUsesUpdatedEntryPriceAfterHarvest() public {
        _seedBalancedVault();
        _harvest(100 ether);

        TrancheState memory senior = vault.trancheState(Tranche.Senior);
        assertEq(senior.accountedAssets, 1040 ether);
        assertEq(senior.entryPriceWad, 1.04 ether);

        uint256 bobShares = _deposit(BOB, Tranche.Senior, 104 ether);
        assertEq(bobShares, 100 ether);
        assertEq(_share(Tranche.Senior).balanceOf(BOB), 100 ether);
        assertEq(vault.trancheState(Tranche.Senior).accountedAssets, 1144 ether);
        _assertSettledAccounting();
    }

    function test_globalDepositPauseBlocksNewCapital() public {
        vm.prank(GUARDIAN);
        vault.setGlobalPauses(true, false, false);

        vm.expectRevert();
        vm.prank(ALICE);
        vault.deposit(Tranche.Senior, 1 ether, ALICE);
    }
}
