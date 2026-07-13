// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaFixture } from "../helpers/ArcadiaFixture.sol";
import { TrancheShareToken } from "../../src/token/TrancheShareToken.sol";
import { Tranche } from "../../src/types/ArcadiaTypes.sol";

contract RedemptionsTest is ArcadiaFixture {
    function test_redeemBurnsSharesAndReturnsAssets() public {
        _seedBalancedVault();

        uint256 aliceBefore = asset.balanceOf(ALICE);
        uint256 assetsOut = _redeem(ALICE, Tranche.Senior, 250 ether);

        assertEq(assetsOut, 250 ether);
        assertEq(asset.balanceOf(ALICE), aliceBefore + 250 ether);
        assertEq(_share(Tranche.Senior).balanceOf(ALICE), 750 ether);
        assertEq(_state(Tranche.Senior).accountedAssets, 750 ether);
        assertEq(vault.totalAccountedAssets(), 1750 ether);
        _assertSettledAccounting();
    }

    function test_approvedOperatorCanRedeemOwnerShares() public {
        _seedBalancedVault();

        TrancheShareToken seniorToken = _share(Tranche.Senior);
        vm.prank(ALICE);
        seniorToken.approve(BOB, 100 ether);

        uint256 bobBefore = asset.balanceOf(BOB);
        vm.prank(BOB);
        uint256 assetsOut = vault.redeem(Tranche.Senior, 100 ether, BOB, ALICE);

        assertEq(assetsOut, 100 ether);
        assertEq(asset.balanceOf(BOB), bobBefore + 100 ether);
        assertEq(_share(Tranche.Senior).balanceOf(ALICE), 900 ether);
        assertEq(_share(Tranche.Senior).allowance(ALICE, BOB), 0);
    }

    function test_redemptionPauseBlocksStandardExit() public {
        _seedBalancedVault();

        vm.prank(GUARDIAN);
        vault.setGlobalPauses(false, true, false);

        vm.expectRevert();
        vm.prank(ALICE);
        vault.redeem(Tranche.Senior, 1 ether, ALICE, ALICE);
    }
}
