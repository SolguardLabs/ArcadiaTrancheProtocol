// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { StrategyReport } from "../types/ArcadiaTypes.sol";

interface IArcadiaStrategy {
    event DebtIncreased(uint256 amount, uint256 totalDebt);
    event DebtReduced(uint256 amount, uint256 totalDebt);
    event StrategyGainQuoted(uint256 amount, uint256 totalPendingGain);
    event StrategyLossQuoted(uint256 amount, uint256 totalPendingLoss);
    event StrategyReportPublished(
        uint256 totalDebt,
        uint256 estimatedAssets,
        uint256 liquidAssets,
        uint256 pendingGain,
        uint256 pendingLoss
    );

    function asset() external view returns (address);
    function vault() external view returns (address);
    function totalDebt() external view returns (uint256);
    function estimatedTotalAssets() external view returns (uint256);
    function liquidAssets() external view returns (uint256);
    function pendingGain() external view returns (uint256);
    function pendingLoss() external view returns (uint256);
    function report() external view returns (StrategyReport memory);
    function receiveDebt(uint256 amount) external;
    function returnDebt(uint256 amount) external;
}
