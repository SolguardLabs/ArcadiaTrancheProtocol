// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";

import { ArcadiaCheckpointRegistry } from "../src/accounting/ArcadiaCheckpointRegistry.sol";
import { ReserveLedger } from "../src/accounting/ReserveLedger.sol";
import { ArcadiaTimelock } from "../src/governance/ArcadiaTimelock.sol";
import { ArcadiaNavOracle } from "../src/oracle/ArcadiaNavOracle.sol";
import { TrancheParameterStore } from "../src/policy/TrancheParameterStore.sol";
import { RedemptionQueue } from "../src/queue/RedemptionQueue.sol";
import { ArcadiaTrancheVault } from "../src/vault/ArcadiaTrancheVault.sol";
import { ArcadiaLens } from "../src/views/ArcadiaLens.sol";
import { ArcadiaMonitor } from "../src/views/ArcadiaMonitor.sol";
import { ArcadiaRiskOracle } from "../src/risk/ArcadiaRiskOracle.sol";
import { ArcadiaScenarioEngine } from "../src/risk/ArcadiaScenarioEngine.sol";
import { ArcadiaStrategyRegistry } from "../src/vault/ArcadiaStrategyRegistry.sol";

contract DeployArcadia is Script {
    struct Deployment {
        ArcadiaTrancheVault vault;
        ArcadiaRiskOracle riskOracle;
        ArcadiaNavOracle navOracle;
        ArcadiaStrategyRegistry strategyRegistry;
        TrancheParameterStore parameterStore;
        RedemptionQueue redemptionQueue;
        ReserveLedger reserveLedger;
        ArcadiaCheckpointRegistry checkpoints;
        ArcadiaScenarioEngine scenarioEngine;
        ArcadiaTimelock timelock;
        ArcadiaLens lens;
        ArcadiaMonitor monitor;
    }

    function run() external returns (Deployment memory deployment) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address asset = vm.envAddress("ARCADIA_ASSET");
        address admin = vm.envOr("ARCADIA_ADMIN", vm.addr(deployerKey));
        address treasury = vm.envAddress("ARCADIA_TREASURY");
        address lossReceiver = vm.envAddress("ARCADIA_LOSS_RECEIVER");
        uint64 redemptionDelay = _envUint64("ARCADIA_REDEMPTION_DELAY", 1 days);
        uint64 governanceDelay = _envUint64("ARCADIA_GOVERNANCE_DELAY", 2 days);
        uint64 governanceGrace = _envUint64("ARCADIA_GOVERNANCE_GRACE", 7 days);

        vm.startBroadcast(deployerKey);
        deployment.vault = new ArcadiaTrancheVault(asset, admin, treasury, lossReceiver);
        deployment.riskOracle = new ArcadiaRiskOracle(admin);
        deployment.navOracle = new ArcadiaNavOracle(admin);
        deployment.strategyRegistry = new ArcadiaStrategyRegistry(admin, address(deployment.vault));
        deployment.parameterStore = new TrancheParameterStore(admin);
        deployment.redemptionQueue =
            new RedemptionQueue(admin, address(deployment.vault), redemptionDelay);
        deployment.reserveLedger = new ReserveLedger(admin);
        deployment.checkpoints = new ArcadiaCheckpointRegistry(admin, address(deployment.vault));
        deployment.scenarioEngine = new ArcadiaScenarioEngine();
        deployment.timelock = new ArcadiaTimelock(admin, governanceDelay, governanceGrace);
        deployment.lens = new ArcadiaLens(address(deployment.vault));
        deployment.monitor = new ArcadiaMonitor(address(deployment.vault));
        vm.stopBroadcast();
    }

    function _envUint64(string memory name, uint256 defaultValue)
        internal
        view
        returns (uint64 value)
    {
        uint256 configured = vm.envOr(name, defaultValue);
        require(configured <= type(uint64).max, "deployment parameter exceeds uint64");
        value = uint64(configured);
    }
}
