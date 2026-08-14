// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaCheckpointRegistry } from "../../src/accounting/ArcadiaCheckpointRegistry.sol";
import {
    Arcadia__CheckpointMismatch,
    Arcadia__InsufficientShares,
    Arcadia__MinimumAssetsNotMet,
    Arcadia__RequestNotReady,
    Arcadia__Unauthorized
} from "../../src/errors/ArcadiaErrors.sol";
import { RedemptionQueue } from "../../src/queue/RedemptionQueue.sol";
import { ArcadiaRiskOracle } from "../../src/risk/ArcadiaRiskOracle.sol";
import { ArcadiaTypes, Tranche } from "../../src/types/ArcadiaTypes.sol";
import { ArcadiaFixture } from "../helpers/ArcadiaFixture.sol";

contract OperationalControlsTest is ArcadiaFixture {
    ArcadiaCheckpointRegistry internal checkpoints;
    RedemptionQueue internal queue;

    function setUp() public override {
        super.setUp();
        checkpoints = new ArcadiaCheckpointRegistry(ADMIN, address(vault));
        queue = new RedemptionQueue(ADMIN, address(vault), 1 days);
    }

    function test_checkpointFormsAppendOnlyChainAndDetectsStateDrift() public {
        _seedBalancedVault();
        bytes32 navDigest = keccak256("nav-2026-08-15T00:00:00Z");
        bytes32 configDigest = keccak256("arcadia-production-config-v1");

        vm.prank(ADMIN);
        ArcadiaCheckpointRegistry.Checkpoint memory first =
            checkpoints.capture(navDigest, configDigest);
        ArcadiaCheckpointRegistry.Checkpoint memory verified = checkpoints.requireCurrent(1);
        assertEq(verified.checkpointDigest, first.checkpointDigest);
        assertEq(first.previousDigest, bytes32(0));

        _deposit(ALICE, Tranche.Senior, 10 ether);
        bytes32 observed = checkpoints.currentStateDigest();
        vm.expectRevert(
            abi.encodeWithSelector(
                Arcadia__CheckpointMismatch.selector, first.stateDigest, observed
            )
        );
        checkpoints.requireCurrent(1);

        vm.prank(ADMIN);
        ArcadiaCheckpointRegistry.Checkpoint memory second =
            checkpoints.capture(keccak256("nav-2"), configDigest);
        assertEq(second.sequence, 2);
        assertEq(second.previousDigest, first.checkpointDigest);
        assertNotEq(second.checkpointDigest, first.checkpointDigest);
    }

    function test_queueReservesAvailableSharesAndEnforcesExecutionFloor() public {
        _deposit(ALICE, Tranche.Senior, 1000 ether);

        vm.prank(ALICE);
        uint256 requestId =
            queue.createRequest(Tranche.Senior, ALICE, ALICE, 400 ether, 390 ether, 1 hours);

        RedemptionQueue.RedemptionRequest memory request_ = queue.request(requestId);
        assertEq(request_.executableAt, block.timestamp + 1 days);
        assertEq(queue.ownerPendingShares(ALICE, uint8(Tranche.Senior)), 400 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Arcadia__InsufficientShares.selector, 601 ether, 600 ether)
        );
        vm.prank(ALICE);
        queue.createRequest(Tranche.Senior, ALICE, ALICE, 601 ether, 0, 1 days);

        vm.expectRevert(
            abi.encodeWithSelector(
                Arcadia__RequestNotReady.selector, requestId, request_.executableAt
            )
        );
        vm.prank(address(vault));
        queue.markClaimed(requestId, 400 ether);

        vm.warp(request_.executableAt);
        vm.expectRevert(
            abi.encodeWithSelector(Arcadia__MinimumAssetsNotMet.selector, 389 ether, 390 ether)
        );
        vm.prank(address(vault));
        queue.markClaimed(requestId, 389 ether);

        vm.prank(address(vault));
        queue.markClaimed(requestId, 400 ether);
        assertEq(queue.pendingShares(), 0);
        assertEq(queue.claimedRequests(), 1);
    }

    function test_queueRejectsThirdPartyRequestCreation() public {
        _deposit(ALICE, Tranche.Senior, 1000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Arcadia__Unauthorized.selector, bytes32("REQUEST_OWNER"), BOB)
        );
        vm.prank(BOB);
        queue.createRequest(Tranche.Senior, ALICE, BOB, 100 ether, 0, 1 days);
    }

    function test_riskOracleRejectsUninitializedFreshnessCheck() public {
        ArcadiaRiskOracle oracle = new ArcadiaRiskOracle(ADMIN);

        vm.expectRevert();
        oracle.requireFreshObservation(keccak256("ETH-USD"), 1 hours);
    }
}
