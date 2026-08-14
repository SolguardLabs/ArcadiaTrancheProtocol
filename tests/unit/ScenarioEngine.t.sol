// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { Arcadia__InvalidBps } from "../../src/errors/ArcadiaErrors.sol";
import { ArcadiaScenarioEngine } from "../../src/risk/ArcadiaScenarioEngine.sol";

contract ScenarioEngineTest is Test {
    ArcadiaScenarioEngine internal engine;

    function setUp() public {
        engine = new ArcadiaScenarioEngine();
    }

    function test_assessAppliesJuniorFirstWaterfallAndLiquidityHaircut() public view {
        ArcadiaScenarioEngine.Portfolio memory portfolio = ArcadiaScenarioEngine.Portfolio({
            seniorAssets: 1000 ether,
            mezzanineAssets: 500 ether,
            juniorAssets: 500 ether,
            liquidAssets: 1500 ether
        });
        ArcadiaScenarioEngine.Shock memory shock = ArcadiaScenarioEngine.Shock({
            lossBps: 4000,
            liquidityHaircutBps: 2000,
            correlationBps: 3000,
            concentrationBps: 5000,
            minimumLiquidBufferBps: 6000
        });

        ArcadiaScenarioEngine.ScenarioResult memory result = engine.assess(portfolio, shock);

        assertEq(result.grossLoss, 800 ether);
        assertEq(result.juniorLoss, 500 ether);
        assertEq(result.mezzanineLoss, 300 ether);
        assertEq(result.seniorLoss, 0);
        assertEq(result.postSeniorAssets, 1000 ether);
        assertEq(result.postMezzanineAssets, 200 ether);
        assertEq(result.stressedLiquidity, 1200 ether);
        assertEq(result.requiredLiquidity, 720 ether);
        assertEq(result.liquidityShortfall, 0);
        assertEq(result.seniorCoverageBps, 2000);
        assertEq(result.riskScoreBps, 3500);
        assertEq(uint8(result.tier), uint8(ArcadiaScenarioEngine.RiskTier.Standard));
        assertTrue(result.solvent);
        assertNotEq(result.scenarioDigest, bytes32(0));
    }

    function test_assessRestrictsScenarioWhenSeniorAbsorbsLoss() public view {
        ArcadiaScenarioEngine.Portfolio memory portfolio = ArcadiaScenarioEngine.Portfolio({
            seniorAssets: 1000 ether,
            mezzanineAssets: 200 ether,
            juniorAssets: 100 ether,
            liquidAssets: 1300 ether
        });
        ArcadiaScenarioEngine.Shock memory shock = ArcadiaScenarioEngine.Shock({
            lossBps: 5000,
            liquidityHaircutBps: 0,
            correlationBps: 1000,
            concentrationBps: 1000,
            minimumLiquidBufferBps: 1000
        });

        ArcadiaScenarioEngine.ScenarioResult memory result = engine.assess(portfolio, shock);

        assertEq(result.grossLoss, 650 ether);
        assertEq(result.juniorLoss, 100 ether);
        assertEq(result.mezzanineLoss, 200 ether);
        assertEq(result.seniorLoss, 350 ether);
        assertEq(uint8(result.tier), uint8(ArcadiaScenarioEngine.RiskTier.Restricted));
    }

    function test_assessExposesLiquidityShortfallIndependentlyFromSolvency() public view {
        ArcadiaScenarioEngine.Portfolio memory portfolio = ArcadiaScenarioEngine.Portfolio({
            seniorAssets: 1000 ether,
            mezzanineAssets: 500 ether,
            juniorAssets: 500 ether,
            liquidAssets: 200 ether
        });
        ArcadiaScenarioEngine.Shock memory shock = ArcadiaScenarioEngine.Shock({
            lossBps: 1000,
            liquidityHaircutBps: 5000,
            correlationBps: 0,
            concentrationBps: 0,
            minimumLiquidBufferBps: 5000
        });

        ArcadiaScenarioEngine.ScenarioResult memory result = engine.assess(portfolio, shock);

        assertEq(result.stressedLiquidity, 100 ether);
        assertEq(result.requiredLiquidity, 900 ether);
        assertEq(result.liquidityShortfall, 800 ether);
        assertFalse(result.solvent);
    }

    function test_assessRejectsNonCanonicalBasisPoints() public {
        ArcadiaScenarioEngine.Portfolio memory portfolio = ArcadiaScenarioEngine.Portfolio({
            seniorAssets: 1 ether,
            mezzanineAssets: 1 ether,
            juniorAssets: 1 ether,
            liquidAssets: 3 ether
        });
        ArcadiaScenarioEngine.Shock memory shock = ArcadiaScenarioEngine.Shock({
            lossBps: 10_001,
            liquidityHaircutBps: 0,
            correlationBps: 0,
            concentrationBps: 0,
            minimumLiquidBufferBps: 0
        });

        vm.expectRevert(abi.encodeWithSelector(Arcadia__InvalidBps.selector, 10_001));
        engine.assess(portfolio, shock);
    }
}
