// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    HarvestReport,
    LossReport,
    ProtocolSnapshot,
    Tranche,
    TrancheConfig,
    TrancheState
} from "../types/ArcadiaTypes.sol";

interface IArcadiaVault {
    event Deposited(
        Tranche indexed tranche,
        address indexed caller,
        address indexed receiver,
        uint256 assets,
        uint256 shares
    );
    event Redeemed(
        Tranche indexed tranche,
        address indexed caller,
        address indexed owner,
        address receiver,
        uint256 shares,
        uint256 assets
    );
    event HarvestRecorded(
        uint256 indexed harvestId,
        address indexed keeper,
        uint256 amount,
        uint256 seniorYield,
        uint256 mezzanineYield,
        uint256 juniorYield,
        uint256 protocolFee
    );
    event LossReported(
        uint256 indexed reportId,
        address indexed reporter,
        uint256 amount,
        uint256 juniorLoss,
        uint256 mezzanineLoss,
        uint256 seniorLoss,
        bytes32 reasonHash
    );
    event LossReportSettled(uint256 indexed reportId, uint256 residualAfter);
    event EmergencyModeEntered(address indexed guardian, uint256 settledReportId);
    event EmergencyModeExited(address indexed governor);

    function asset() external view returns (address);
    function treasury() external view returns (address);
    function lossReceiver() external view returns (address);
    function seniorShare() external view returns (address);
    function mezzanineShare() external view returns (address);
    function juniorShare() external view returns (address);
    function openLossReportId() external view returns (uint256);
    function totalAccountedAssets() external view returns (uint256);
    function sharedResidualValue() external view returns (uint256);
    function trancheConfig(Tranche tranche) external view returns (TrancheConfig memory);
    function trancheState(Tranche tranche) external view returns (TrancheState memory);
    function lossReport(uint256 reportId) external view returns (LossReport memory);
    function latestHarvest() external view returns (HarvestReport memory);
    function snapshot() external view returns (ProtocolSnapshot memory);
    function trancheShareToken(Tranche tranche) external view returns (address);
    function previewDeposit(Tranche tranche, uint256 assets) external view returns (uint256);
    function previewRedeem(Tranche tranche, uint256 shares) external view returns (uint256);
    function deposit(Tranche tranche, uint256 assets, address receiver) external returns (uint256);
    function redeem(Tranche tranche, uint256 shares, address receiver, address owner)
        external
        returns (uint256);
    function harvest(uint256 amount, bytes32 sourceHash) external returns (uint256);
    function reportLoss(uint256 amount, bytes32 reasonHash) external returns (uint256);
    function settleLossReport(uint256 reportId) external;
    function enterEmergencyMode() external;
    function emergencyRedeem(Tranche tranche, uint256 shares, address receiver, address owner)
        external
        returns (uint256);
}
