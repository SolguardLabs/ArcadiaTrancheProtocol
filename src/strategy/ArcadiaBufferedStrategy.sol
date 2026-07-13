// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    Arcadia__InsufficientAssets,
    Arcadia__Unauthorized,
    Arcadia__UnsupportedTokenBehavior,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IArcadiaStrategy } from "../interfaces/IArcadiaStrategy.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { StrategyReport, StrategyStatus } from "../types/ArcadiaTypes.sol";

/// @notice Simple buffered strategy adapter used for local Arcadia deployments.
contract ArcadiaBufferedStrategy is IArcadiaStrategy {
    using SafeTransferLib for address;

    IERC20 private immutable _asset;
    address public override vault;
    address public manager;
    StrategyStatus public status = StrategyStatus.Active;

    uint256 public override totalDebt;
    uint256 public override pendingGain;
    uint256 public override pendingLoss;
    uint64 public lastReport;

    event ManagerUpdated(address indexed previousManager, address indexed newManager);
    event StrategyStatusUpdated(StrategyStatus indexed status);

    modifier onlyVault() {
        if (msg.sender != vault) revert Arcadia__Unauthorized(bytes32("VAULT"), msg.sender);
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) revert Arcadia__Unauthorized(bytes32("MANAGER"), msg.sender);
        _;
    }

    constructor(address asset_, address vault_, address manager_) {
        if (asset_ == address(0) || vault_ == address(0) || manager_ == address(0)) {
            revert Arcadia__ZeroAddress();
        }
        _asset = IERC20(asset_);
        vault = vault_;
        manager = manager_;
        lastReport = uint64(block.timestamp);
    }

    function asset() external view override returns (address) {
        return address(_asset);
    }

    function setManager(address newManager) external onlyManager {
        if (newManager == address(0)) revert Arcadia__ZeroAddress();
        address previous = manager;
        manager = newManager;
        emit ManagerUpdated(previous, newManager);
    }

    function setStatus(StrategyStatus newStatus) external onlyManager {
        status = newStatus;
        emit StrategyStatusUpdated(newStatus);
    }

    function receiveDebt(uint256 amount) external override onlyVault {
        if (amount == 0) revert Arcadia__ZeroAmount();
        uint256 beforeBalance = _asset.balanceOf(address(this));
        address(_asset).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = _asset.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert Arcadia__UnsupportedTokenBehavior();
        totalDebt += amount;
        emit DebtIncreased(amount, totalDebt);
    }

    function returnDebt(uint256 amount) external override onlyVault {
        if (amount == 0) revert Arcadia__ZeroAmount();
        if (amount > _asset.balanceOf(address(this))) {
            revert Arcadia__InsufficientAssets(amount, _asset.balanceOf(address(this)));
        }
        uint256 debtReduction = amount > totalDebt ? totalDebt : amount;
        totalDebt -= debtReduction;
        address(_asset).safeTransfer(vault, amount);
        emit DebtReduced(debtReduction, totalDebt);
    }

    function quoteGain(uint256 amount) external onlyManager {
        pendingGain += amount;
        emit StrategyGainQuoted(amount, pendingGain);
    }

    function quoteLoss(uint256 amount) external onlyManager {
        pendingLoss += amount;
        emit StrategyLossQuoted(amount, pendingLoss);
    }

    function clearPending() external onlyManager {
        pendingGain = 0;
        pendingLoss = 0;
        lastReport = uint64(block.timestamp);
        emit StrategyReportPublished(totalDebt, estimatedTotalAssets(), liquidAssets(), 0, 0);
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        uint256 debtAfterLoss = totalDebt > pendingLoss ? totalDebt - pendingLoss : 0;
        return debtAfterLoss + pendingGain;
    }

    function liquidAssets() public view override returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function report() external view override returns (StrategyReport memory strategyReport) {
        strategyReport = StrategyReport({
            strategy: address(this),
            totalDebt: totalDebt,
            estimatedAssets: estimatedTotalAssets(),
            liquidAssets: liquidAssets(),
            pendingGain: pendingGain,
            pendingLoss: pendingLoss,
            lastReport: lastReport,
            status: status
        });
    }
}
