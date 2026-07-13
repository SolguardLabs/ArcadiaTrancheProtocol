// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";

import { ArcadiaTrancheVault } from "../src/vault/ArcadiaTrancheVault.sol";
import { ArcadiaLens } from "../src/views/ArcadiaLens.sol";
import { ArcadiaMonitor } from "../src/views/ArcadiaMonitor.sol";
import { ArcadiaRiskOracle } from "../src/risk/ArcadiaRiskOracle.sol";

contract DeployArcadia is Script {
    function run()
        external
        returns (
            ArcadiaTrancheVault vault,
            ArcadiaRiskOracle riskOracle,
            ArcadiaLens lens,
            ArcadiaMonitor monitor
        )
    {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address asset = vm.envAddress("ARCADIA_ASSET");
        address admin = vm.envOr("ARCADIA_ADMIN", vm.addr(deployerKey));
        address treasury = vm.envAddress("ARCADIA_TREASURY");
        address lossReceiver = vm.envAddress("ARCADIA_LOSS_RECEIVER");

        vm.startBroadcast(deployerKey);
        vault = new ArcadiaTrancheVault(asset, admin, treasury, lossReceiver);
        riskOracle = new ArcadiaRiskOracle(admin);
        lens = new ArcadiaLens(address(vault));
        monitor = new ArcadiaMonitor(address(vault));
        vm.stopBroadcast();
    }
}
