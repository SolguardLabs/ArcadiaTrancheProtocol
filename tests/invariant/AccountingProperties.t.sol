// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaFixture } from "../helpers/ArcadiaFixture.sol";
import { Tranche } from "../../src/types/ArcadiaTypes.sol";

contract AccountingPropertiesTest is ArcadiaFixture {
    function test_protocolSnapshotMatchesTrancheBooksAfterSettledFlows() public {
        _seedBalancedVault();
        _harvest(150 ether);
        uint256 reportId = _reportLoss(300 ether);
        _settle(reportId);
        _redeem(ALICE, Tranche.Senior, 100 ether);
        _redeem(BOB, Tranche.Mezzanine, 100 ether);

        _assertSettledAccounting();
        assertTrue(monitor.pricesSyncedWhenSettled());
        assertTrue(monitor.canProcessStandardFlow());
    }
}
