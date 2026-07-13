// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__AssetAmountZero,
    Arcadia__DepositCapExceeded,
    Arcadia__DepositsPaused,
    Arcadia__EmergencyModeActive,
    Arcadia__EmergencyModeInactive,
    Arcadia__HarvestPaused,
    Arcadia__InsufficientAssets,
    Arcadia__InsufficientLiquidity,
    Arcadia__InvalidBps,
    Arcadia__InvalidFee,
    Arcadia__InvalidTranche,
    Arcadia__LossExceedsAssets,
    Arcadia__LossExceedsLiquidity,
    Arcadia__LossReportNotFound,
    Arcadia__LossReportNotPending,
    Arcadia__LossReportPending,
    Arcadia__Reentrancy,
    Arcadia__RedemptionsPaused,
    Arcadia__ShareAmountZero,
    Arcadia__TokenNotRecoverable,
    Arcadia__TrancheDepositsDisabled,
    Arcadia__TrancheRedemptionsDisabled,
    Arcadia__UnsupportedTokenBehavior,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { IArcadiaVault } from "../interfaces/IArcadiaVault.sol";
import { FixedPointMath } from "../libraries/FixedPointMath.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { WaterfallMath } from "../libraries/WaterfallMath.sol";
import { TrancheShareToken } from "../token/TrancheShareToken.sol";
import {
    ArcadiaTypes,
    HarvestAllocation,
    HarvestReport,
    LossAllocation,
    LossReport,
    LossReportStatus,
    ProtocolSnapshot,
    Tranche,
    TrancheConfig,
    TrancheState
} from "../types/ArcadiaTypes.sol";

/// @title ArcadiaTrancheVault
/// @notice Three-tranche vault with senior, mezzanine, and junior accounting.
contract ArcadiaTrancheVault is ArcadiaRoles, IArcadiaVault {
    using FixedPointMath for uint256;
    using SafeTransferLib for address;

    uint16 public constant SENIOR_PROTECTION_BPS = 5000;
    uint16 public constant MEZZANINE_PROTECTION_BPS = 3000;

    IERC20 private immutable _asset;
    TrancheShareToken private immutable _seniorShare;
    TrancheShareToken private immutable _mezzanineShare;
    TrancheShareToken private immutable _juniorShare;

    address public override treasury;
    address public override lossReceiver;

    uint256 public override totalAccountedAssets;
    uint256 public override sharedResidualValue;
    uint256 public totalFeesAccrued;
    uint256 public latestHarvestId;
    uint256 public latestLossReportId;
    uint256 public override openLossReportId;

    bool public depositsPaused;
    bool public redemptionsPaused;
    bool public harvestPaused;
    bool public emergencyMode;

    uint256 private _reentrancyState = 1;

    mapping(uint8 => TrancheConfig) private _configs;
    mapping(uint8 => TrancheState) private _states;
    mapping(uint256 => LossReport) private _lossReports;
    mapping(uint256 => HarvestReport) private _harvestReports;

    event TrancheConfigUpdated(
        Tranche indexed tranche,
        uint16 depositFeeBps,
        uint16 redemptionFeeBps,
        uint16 harvestTargetBps,
        uint16 maxDepositShareBps,
        uint16 minimumCoverageBps,
        bool depositsEnabled,
        bool redemptionsEnabled
    );
    event TreasuryUpdated(address indexed previousTreasury, address indexed newTreasury);
    event LossReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);
    event GlobalPauseUpdated(bool depositsPaused, bool redemptionsPaused, bool harvestPaused);
    event TranchePriceUpdated(
        Tranche indexed tranche,
        uint256 entryPriceWad,
        uint256 exitPriceWad,
        uint256 accountedAssets,
        uint256 totalShares
    );
    event ProtectionDrawn(
        Tranche indexed beneficiary,
        uint256 juniorAssetsUsed,
        uint256 mezzanineAssetsUsed,
        uint256 requestedAssets
    );
    event FeesClaimed(address indexed treasury, uint256 amount);
    event ForeignTokenRecovered(address indexed token, address indexed recipient, uint256 amount);

    modifier nonReentrant() {
        if (_reentrancyState != 1) revert Arcadia__Reentrancy();
        _reentrancyState = 2;
        _;
        _reentrancyState = 1;
    }

    modifier onlyGovernor() {
        _checkRole(ArcadiaTypes.GOVERNOR_ROLE, msg.sender);
        _;
    }

    modifier onlyKeeper() {
        if (
            !hasRole(ArcadiaTypes.KEEPER_ROLE, msg.sender)
                && !hasRole(ArcadiaTypes.GOVERNOR_ROLE, msg.sender)
        ) {
            _checkRole(ArcadiaTypes.KEEPER_ROLE, msg.sender);
        }
        _;
    }

    modifier onlyReporter() {
        if (
            !hasRole(ArcadiaTypes.REPORTER_ROLE, msg.sender)
                && !hasRole(ArcadiaTypes.GOVERNOR_ROLE, msg.sender)
        ) {
            _checkRole(ArcadiaTypes.REPORTER_ROLE, msg.sender);
        }
        _;
    }

    modifier onlyGuardian() {
        if (
            !hasRole(ArcadiaTypes.GUARDIAN_ROLE, msg.sender)
                && !hasRole(ArcadiaTypes.GOVERNOR_ROLE, msg.sender)
        ) {
            _checkRole(ArcadiaTypes.GUARDIAN_ROLE, msg.sender);
        }
        _;
    }

    constructor(address asset_, address admin_, address treasury_, address lossReceiver_)
        ArcadiaRoles(admin_)
    {
        if (asset_ == address(0) || treasury_ == address(0) || lossReceiver_ == address(0)) {
            revert Arcadia__ZeroAddress();
        }

        _asset = IERC20(asset_);
        treasury = treasury_;
        lossReceiver = lossReceiver_;

        _seniorShare = new TrancheShareToken("Arcadia Senior Share", "aSEN", 18, address(this));
        _mezzanineShare =
            new TrancheShareToken("Arcadia Mezzanine Share", "aMEZ", 18, address(this));
        _juniorShare = new TrancheShareToken("Arcadia Junior Share", "aJUN", 18, address(this));

        _grantInitialRole(ArcadiaTypes.GOVERNOR_ROLE, admin_);
        _grantInitialRole(ArcadiaTypes.KEEPER_ROLE, admin_);
        _grantInitialRole(ArcadiaTypes.REPORTER_ROLE, admin_);
        _grantInitialRole(ArcadiaTypes.GUARDIAN_ROLE, admin_);
        _grantInitialRole(ArcadiaTypes.RISK_MANAGER_ROLE, admin_);
        _grantInitialRole(ArcadiaTypes.STRATEGIST_ROLE, admin_);

        _setDefaultTrancheConfig();
        _initializePrices();
    }

    function asset() external view override returns (address) {
        return address(_asset);
    }

    function seniorShare() external view override returns (address) {
        return address(_seniorShare);
    }

    function mezzanineShare() external view override returns (address) {
        return address(_mezzanineShare);
    }

    function juniorShare() external view override returns (address) {
        return address(_juniorShare);
    }

    function trancheShareToken(Tranche tranche) public view override returns (address) {
        return address(_shareToken(tranche));
    }

    function trancheConfig(Tranche tranche) external view override returns (TrancheConfig memory) {
        return _configs[_idx(tranche)];
    }

    function trancheState(Tranche tranche) public view override returns (TrancheState memory) {
        return _states[_idx(tranche)];
    }

    function lossReport(uint256 reportId) external view override returns (LossReport memory) {
        LossReport memory report = _lossReports[reportId];
        if (report.status == LossReportStatus.None) revert Arcadia__LossReportNotFound(reportId);
        return report;
    }

    function latestHarvest() external view override returns (HarvestReport memory) {
        return _harvestReports[latestHarvestId];
    }

    function snapshot() external view override returns (ProtocolSnapshot memory protocol) {
        protocol = ProtocolSnapshot({
            totalAccountedAssets: totalAccountedAssets,
            liquidAssets: _asset.balanceOf(address(this)),
            sharedResidualValue: sharedResidualValue,
            totalFeesAccrued: totalFeesAccrued,
            latestHarvestId: latestHarvestId,
            latestLossReportId: latestLossReportId,
            openLossReportId: openLossReportId,
            depositsPaused: depositsPaused,
            redemptionsPaused: redemptionsPaused,
            harvestPaused: harvestPaused,
            emergencyMode: emergencyMode
        });
    }

    function setTreasury(address newTreasury) external onlyGovernor {
        if (newTreasury == address(0)) revert Arcadia__ZeroAddress();
        address previous = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(previous, newTreasury);
    }

    function setLossReceiver(address newReceiver) external onlyGovernor {
        if (newReceiver == address(0)) revert Arcadia__ZeroAddress();
        address previous = lossReceiver;
        lossReceiver = newReceiver;
        emit LossReceiverUpdated(previous, newReceiver);
    }

    function setGlobalPauses(bool pauseDeposits, bool pauseRedemptions, bool pauseHarvests)
        external
        onlyGuardian
    {
        depositsPaused = pauseDeposits;
        redemptionsPaused = pauseRedemptions;
        harvestPaused = pauseHarvests;
        emit GlobalPauseUpdated(pauseDeposits, pauseRedemptions, pauseHarvests);
    }

    function configureTranche(Tranche tranche, TrancheConfig calldata config)
        external
        onlyGovernor
    {
        _validateConfig(config);
        _configs[_idx(tranche)] = config;
        emit TrancheConfigUpdated(
            tranche,
            config.depositFeeBps,
            config.redemptionFeeBps,
            config.harvestTargetBps,
            config.maxDepositShareBps,
            config.minimumCoverageBps,
            config.depositsEnabled,
            config.redemptionsEnabled
        );
    }

    function previewDeposit(Tranche tranche, uint256 assets)
        external
        view
        override
        returns (uint256)
    {
        uint8 id = _idx(tranche);
        TrancheConfig memory config = _configs[id];
        uint256 fee = assets.bpsOf(config.depositFeeBps);
        uint256 netAssets = assets - fee;
        return WaterfallMath.depositShares(netAssets, _states[id].entryPriceWad);
    }

    function previewRedeem(Tranche tranche, uint256 shares) public view override returns (uint256) {
        uint8 id = _idx(tranche);
        uint256 price = emergencyMode ? _liquidationPrice(id) : _states[id].exitPriceWad;
        uint256 grossAssets = WaterfallMath.redeemAssets(shares, price);
        uint256 fee = grossAssets.bpsOf(_configs[id].redemptionFeeBps);
        return grossAssets - fee;
    }

    function deposit(Tranche tranche, uint256 assets, address receiver)
        external
        override
        nonReentrant
        returns (uint256 shares)
    {
        if (receiver == address(0)) revert Arcadia__ZeroAddress();
        if (assets == 0) revert Arcadia__ZeroAmount();
        if (emergencyMode) revert Arcadia__EmergencyModeActive();
        if (depositsPaused) revert Arcadia__DepositsPaused();

        uint8 id = _idx(tranche);
        TrancheConfig memory config = _configs[id];
        if (!config.depositsEnabled) revert Arcadia__TrancheDepositsDisabled(id);

        uint256 beforeBalance = _asset.balanceOf(address(this));
        address(_asset).safeTransferFrom(msg.sender, address(this), assets);
        uint256 received = _asset.balanceOf(address(this)) - beforeBalance;
        if (received != assets) revert Arcadia__UnsupportedTokenBehavior();

        uint256 fee = assets.bpsOf(config.depositFeeBps);
        uint256 netAssets = assets - fee;
        if (netAssets == 0) revert Arcadia__AssetAmountZero();

        shares = WaterfallMath.depositShares(netAssets, _states[id].entryPriceWad);
        if (shares == 0) revert Arcadia__ShareAmountZero();

        _enforceDepositShareCap(id, netAssets);

        _states[id].accountedAssets += netAssets;
        _states[id].feesAccrued += fee;
        totalAccountedAssets += netAssets;
        totalFeesAccrued += fee;

        _shareToken(tranche).mint(receiver, shares);
        _refreshAfterBookChange(id);
        _syncResidualWhenSettled();

        emit Deposited(tranche, msg.sender, receiver, netAssets, shares);
    }

    function redeem(Tranche tranche, uint256 shares, address receiver, address owner)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (receiver == address(0) || owner == address(0)) revert Arcadia__ZeroAddress();
        if (shares == 0) revert Arcadia__ZeroAmount();
        if (emergencyMode) revert Arcadia__EmergencyModeActive();
        if (redemptionsPaused) revert Arcadia__RedemptionsPaused();

        uint8 id = _idx(tranche);
        TrancheConfig memory config = _configs[id];
        if (!config.redemptionsEnabled) revert Arcadia__TrancheRedemptionsDisabled(id);

        TrancheShareToken share = _shareToken(tranche);
        if (owner != msg.sender) share.spendAllowance(owner, msg.sender, shares);

        uint256 grossAssets = WaterfallMath.redeemAssets(shares, _states[id].exitPriceWad);
        uint256 bookAssets = WaterfallMath.redeemAssets(shares, _states[id].entryPriceWad);
        if (grossAssets == 0) revert Arcadia__AssetAmountZero();

        uint256 fee = grossAssets.bpsOf(config.redemptionFeeBps);
        assets = grossAssets - fee;
        if (_asset.balanceOf(address(this)) < assets) {
            revert Arcadia__InsufficientLiquidity(assets, _asset.balanceOf(address(this)));
        }

        share.burnFrom(owner, shares);
        _debitRedemption(id, grossAssets, bookAssets);
        _states[id].feesAccrued += fee;
        totalFeesAccrued += fee;

        if (assets != 0) address(_asset).safeTransfer(receiver, assets);
        _refreshAfterBookChange(id);
        _syncResidualWhenSettled();

        emit Redeemed(tranche, msg.sender, owner, receiver, shares, assets);
    }

    function harvest(uint256 amount, bytes32 sourceHash)
        external
        override
        onlyKeeper
        nonReentrant
        returns (uint256 harvestId)
    {
        if (amount == 0) revert Arcadia__ZeroAmount();
        if (emergencyMode) revert Arcadia__EmergencyModeActive();
        if (harvestPaused) revert Arcadia__HarvestPaused();

        uint256 beforeBalance = _asset.balanceOf(address(this));
        address(_asset).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = _asset.balanceOf(address(this)) - beforeBalance;
        if (received != amount) revert Arcadia__UnsupportedTokenBehavior();

        HarvestAllocation memory allocation = WaterfallMath.allocateHarvest(
            amount,
            _states[uint8(Tranche.Senior)].accountedAssets,
            _states[uint8(Tranche.Mezzanine)].accountedAssets,
            _configs[uint8(Tranche.Senior)].harvestTargetBps,
            _configs[uint8(Tranche.Mezzanine)].harvestTargetBps,
            0
        );

        _creditHarvest(uint8(Tranche.Senior), allocation.seniorYield);
        _creditHarvest(uint8(Tranche.Mezzanine), allocation.mezzanineYield);
        _creditHarvest(uint8(Tranche.Junior), allocation.juniorYield);

        totalFeesAccrued += allocation.protocolFee;
        totalAccountedAssets += amount - allocation.protocolFee;

        harvestId = ++latestHarvestId;
        _harvestReports[harvestId] = HarvestReport({
            id: harvestId,
            amount: amount,
            seniorYield: allocation.seniorYield,
            mezzanineYield: allocation.mezzanineYield,
            juniorYield: allocation.juniorYield,
            protocolFee: allocation.protocolFee,
            harvestedAt: uint64(block.timestamp),
            sourceHash: sourceHash,
            keeper: msg.sender
        });

        _refreshAllBookPrices();
        _syncResidualWhenSettled();

        emit HarvestRecorded(
            harvestId,
            msg.sender,
            amount,
            allocation.seniorYield,
            allocation.mezzanineYield,
            allocation.juniorYield,
            allocation.protocolFee
        );
    }

    function reportLoss(uint256 amount, bytes32 reasonHash)
        external
        override
        onlyReporter
        nonReentrant
        returns (uint256 reportId)
    {
        if (amount == 0) revert Arcadia__ZeroAmount();
        if (emergencyMode) revert Arcadia__EmergencyModeActive();
        if (openLossReportId != 0) revert Arcadia__LossReportPending(openLossReportId);
        if (amount > totalAccountedAssets) {
            revert Arcadia__LossExceedsAssets(amount, totalAccountedAssets);
        }
        if (amount > _asset.balanceOf(address(this))) {
            revert Arcadia__LossExceedsLiquidity(amount, _asset.balanceOf(address(this)));
        }

        uint256 residualBefore = sharedResidualValue;
        LossAllocation memory allocation = WaterfallMath.allocateLoss(
            amount,
            _states[uint8(Tranche.Junior)].accountedAssets,
            _states[uint8(Tranche.Mezzanine)].accountedAssets,
            _states[uint8(Tranche.Senior)].accountedAssets
        );
        if (allocation.unallocatedLoss != 0) {
            revert Arcadia__LossExceedsAssets(amount, totalAccountedAssets);
        }

        _applyLoss(uint8(Tranche.Junior), allocation.juniorLoss);
        _applyLoss(uint8(Tranche.Mezzanine), allocation.mezzanineLoss);
        _applyLoss(uint8(Tranche.Senior), allocation.seniorLoss);

        totalAccountedAssets -= amount;
        address(_asset).safeTransfer(lossReceiver, amount);

        // The pending report keeps exit pricing stable while off-chain operators reconcile the
        // write-down and strategy attestations. Settlement refreshes every cached residual value.
        _refreshLossWindowPrices(residualBefore);

        uint256 residualAfter = _subordinatedAssets();
        reportId = ++latestLossReportId;
        openLossReportId = reportId;
        _lossReports[reportId] = LossReport({
            id: reportId,
            amount: amount,
            juniorLoss: allocation.juniorLoss,
            mezzanineLoss: allocation.mezzanineLoss,
            seniorLoss: allocation.seniorLoss,
            residualBefore: residualBefore,
            residualAfter: residualAfter,
            seniorExitPriceWad: _states[uint8(Tranche.Senior)].exitPriceWad,
            reportedAt: uint64(block.timestamp),
            status: LossReportStatus.Pending,
            reasonHash: reasonHash,
            reporter: msg.sender
        });

        emit LossReported(
            reportId,
            msg.sender,
            amount,
            allocation.juniorLoss,
            allocation.mezzanineLoss,
            allocation.seniorLoss,
            reasonHash
        );
    }

    function settleLossReport(uint256 reportId) external override onlyKeeper nonReentrant {
        _settleLossReport(reportId);
    }

    function enterEmergencyMode() external override onlyGuardian nonReentrant {
        uint256 settledReportId;
        if (openLossReportId != 0) {
            settledReportId = openLossReportId;
            _settleLossReport(settledReportId);
        }

        emergencyMode = true;
        depositsPaused = true;
        redemptionsPaused = true;
        harvestPaused = true;
        _refreshAllBookPrices();
        emit EmergencyModeEntered(msg.sender, settledReportId);
    }

    function exitEmergencyMode() external onlyGovernor {
        if (!emergencyMode) revert Arcadia__EmergencyModeInactive();
        emergencyMode = false;
        depositsPaused = false;
        redemptionsPaused = false;
        harvestPaused = false;
        _refreshAllBookPrices();
        emit EmergencyModeExited(msg.sender);
    }

    function emergencyRedeem(Tranche tranche, uint256 shares, address receiver, address owner)
        external
        override
        nonReentrant
        returns (uint256 assets)
    {
        if (!emergencyMode) revert Arcadia__EmergencyModeInactive();
        if (receiver == address(0) || owner == address(0)) revert Arcadia__ZeroAddress();
        if (shares == 0) revert Arcadia__ZeroAmount();

        uint8 id = _idx(tranche);
        TrancheShareToken share = _shareToken(tranche);
        if (owner != msg.sender) share.spendAllowance(owner, msg.sender, shares);

        assets = WaterfallMath.redeemAssets(shares, _liquidationPrice(id));
        if (assets == 0) revert Arcadia__AssetAmountZero();
        if (_asset.balanceOf(address(this)) < assets) {
            revert Arcadia__InsufficientLiquidity(assets, _asset.balanceOf(address(this)));
        }

        share.burnFrom(owner, shares);
        _debitOwnBook(id, assets);
        address(_asset).safeTransfer(receiver, assets);
        _refreshAfterBookChange(id);
        _syncResidualWhenSettled();

        emit Redeemed(tranche, msg.sender, owner, receiver, shares, assets);
    }

    function claimFees() external nonReentrant returns (uint256 amount) {
        amount = totalFeesAccrued;
        if (amount == 0) revert Arcadia__ZeroAmount();
        if (_asset.balanceOf(address(this)) < amount) {
            revert Arcadia__InsufficientLiquidity(amount, _asset.balanceOf(address(this)));
        }
        totalFeesAccrued = 0;
        address(_asset).safeTransfer(treasury, amount);
        emit FeesClaimed(treasury, amount);
    }

    function recoverForeignToken(address token, address recipient, uint256 amount)
        external
        onlyGovernor
    {
        if (token == address(0) || recipient == address(0)) revert Arcadia__ZeroAddress();
        if (token == address(_asset)) revert Arcadia__TokenNotRecoverable(token);
        token.safeTransfer(recipient, amount);
        emit ForeignTokenRecovered(token, recipient, amount);
    }

    function _setDefaultTrancheConfig() internal {
        _configs[uint8(Tranche.Senior)] = TrancheConfig({
            name: "Senior",
            depositFeeBps: 0,
            redemptionFeeBps: 0,
            harvestTargetBps: 400,
            maxDepositShareBps: 10_000,
            minimumCoverageBps: 3000,
            depositsEnabled: true,
            redemptionsEnabled: true
        });
        _configs[uint8(Tranche.Mezzanine)] = TrancheConfig({
            name: "Mezzanine",
            depositFeeBps: 0,
            redemptionFeeBps: 0,
            harvestTargetBps: 900,
            maxDepositShareBps: 10_000,
            minimumCoverageBps: 1500,
            depositsEnabled: true,
            redemptionsEnabled: true
        });
        _configs[uint8(Tranche.Junior)] = TrancheConfig({
            name: "Junior",
            depositFeeBps: 0,
            redemptionFeeBps: 0,
            harvestTargetBps: 0,
            maxDepositShareBps: 10_000,
            minimumCoverageBps: 0,
            depositsEnabled: true,
            redemptionsEnabled: true
        });
    }

    function _initializePrices() internal {
        for (uint8 id; id < 3; ++id) {
            _states[id].entryPriceWad = ArcadiaTypes.WAD;
            _states[id].exitPriceWad = ArcadiaTypes.WAD;
            _states[id].lastPriceUpdate = uint64(block.timestamp);
        }
    }

    function _validateConfig(TrancheConfig memory config) internal pure {
        if (config.depositFeeBps > ArcadiaTypes.MAX_FEE_BPS) {
            revert Arcadia__InvalidFee(config.depositFeeBps);
        }
        if (config.redemptionFeeBps > ArcadiaTypes.MAX_FEE_BPS) {
            revert Arcadia__InvalidFee(config.redemptionFeeBps);
        }
        if (config.harvestTargetBps > ArcadiaTypes.MAX_TRANCHE_BPS) {
            revert Arcadia__InvalidBps(config.harvestTargetBps);
        }
        if (config.maxDepositShareBps > ArcadiaTypes.MAX_TRANCHE_BPS) {
            revert Arcadia__InvalidBps(config.maxDepositShareBps);
        }
        if (config.minimumCoverageBps > ArcadiaTypes.MAX_TRANCHE_BPS) {
            revert Arcadia__InvalidBps(config.minimumCoverageBps);
        }
    }

    function _idx(Tranche tranche) internal pure returns (uint8 id) {
        id = uint8(tranche);
        if (id > uint8(Tranche.Junior)) revert Arcadia__InvalidTranche(id);
    }

    function _shareToken(Tranche tranche) internal view returns (TrancheShareToken) {
        uint8 id = _idx(tranche);
        if (id == uint8(Tranche.Senior)) return _seniorShare;
        if (id == uint8(Tranche.Mezzanine)) return _mezzanineShare;
        return _juniorShare;
    }

    function _shareTokenById(uint8 id) internal view returns (TrancheShareToken) {
        if (id == uint8(Tranche.Senior)) return _seniorShare;
        if (id == uint8(Tranche.Mezzanine)) return _mezzanineShare;
        if (id == uint8(Tranche.Junior)) return _juniorShare;
        revert Arcadia__InvalidTranche(id);
    }

    function _totalShares(uint8 id) internal view returns (uint256) {
        return _shareTokenById(id).totalSupply();
    }

    function _enforceDepositShareCap(uint8 id, uint256 netAssets) internal view {
        uint16 capBps = _configs[id].maxDepositShareBps;
        if (capBps == ArcadiaTypes.MAX_TRANCHE_BPS || totalAccountedAssets == 0) return;

        uint256 resultingTrancheAssets = _states[id].accountedAssets + netAssets;
        uint256 resultingTotalAssets = totalAccountedAssets + netAssets;
        uint256 cap = resultingTotalAssets.bpsOf(capBps);
        if (resultingTrancheAssets > cap) {
            revert Arcadia__DepositCapExceeded(id, resultingTrancheAssets, cap);
        }
    }

    function _creditHarvest(uint8 id, uint256 amount) internal {
        if (amount == 0) return;
        _states[id].accountedAssets += amount;
        _states[id].yieldAccrued += amount;
    }

    function _applyLoss(uint8 id, uint256 amount) internal {
        if (amount == 0) return;
        TrancheState storage state = _states[id];
        if (amount > state.accountedAssets) {
            revert Arcadia__InsufficientAssets(amount, state.accountedAssets);
        }
        state.accountedAssets -= amount;
        state.lossAbsorbed += amount;
    }

    function _debitOwnBook(uint8 id, uint256 assets) internal {
        TrancheState storage state = _states[id];
        if (assets > state.accountedAssets) {
            revert Arcadia__InsufficientAssets(assets, state.accountedAssets);
        }
        state.accountedAssets -= assets;
        totalAccountedAssets -= assets;
    }

    function _debitRedemption(uint8 id, uint256 grossAssets, uint256 bookAssets) internal {
        TrancheState storage state = _states[id];
        uint256 ownDebit = bookAssets.min(grossAssets);
        if (ownDebit > state.accountedAssets) {
            revert Arcadia__InsufficientAssets(ownDebit, state.accountedAssets);
        }

        state.accountedAssets -= ownDebit;
        totalAccountedAssets -= ownDebit;

        if (grossAssets <= ownDebit) {
            return;
        }

        uint256 shortfall = grossAssets - ownDebit;

        if (id == uint8(Tranche.Senior)) {
            (uint256 juniorUsed, uint256 mezzanineUsed) = _drawSubordination(shortfall);
            emit ProtectionDrawn(Tranche.Senior, juniorUsed, mezzanineUsed, shortfall);
            return;
        }

        if (id == uint8(Tranche.Mezzanine)) {
            uint256 juniorUsed = _drawJunior(shortfall);
            emit ProtectionDrawn(Tranche.Mezzanine, juniorUsed, 0, shortfall);
            return;
        }

        revert Arcadia__InsufficientAssets(grossAssets, ownDebit);
    }

    function _drawSubordination(uint256 amount)
        internal
        returns (uint256 juniorUsed, uint256 mezzanineUsed)
    {
        juniorUsed = _drawJunior(amount);
        uint256 remaining = amount - juniorUsed;
        if (remaining != 0) {
            TrancheState storage mezzanine = _states[uint8(Tranche.Mezzanine)];
            mezzanineUsed = remaining.min(mezzanine.accountedAssets);
            mezzanine.accountedAssets -= mezzanineUsed;
            totalAccountedAssets -= mezzanineUsed;
            _reduceResidual(mezzanineUsed);
        }
        if (juniorUsed + mezzanineUsed < amount) {
            revert Arcadia__InsufficientAssets(amount, juniorUsed + mezzanineUsed);
        }
    }

    function _drawJunior(uint256 amount) internal returns (uint256 juniorUsed) {
        TrancheState storage junior = _states[uint8(Tranche.Junior)];
        juniorUsed = amount.min(junior.accountedAssets);
        if (juniorUsed != 0) {
            junior.accountedAssets -= juniorUsed;
            totalAccountedAssets -= juniorUsed;
            _reduceResidual(juniorUsed);
        }
    }

    function _reduceResidual(uint256 amount) internal {
        sharedResidualValue = sharedResidualValue > amount ? sharedResidualValue - amount : 0;
    }

    function _refreshAfterBookChange(uint8 id) internal {
        _refreshBookPrice(id, openLossReportId == 0 || id != uint8(Tranche.Senior));
    }

    function _refreshAllBookPrices() internal {
        _refreshBookPrice(uint8(Tranche.Senior), true);
        _refreshBookPrice(uint8(Tranche.Mezzanine), true);
        _refreshBookPrice(uint8(Tranche.Junior), true);
    }

    function _refreshBookPrice(uint8 id, bool refreshExitPrice) internal {
        TrancheState storage state = _states[id];
        uint256 shares = _totalShares(id);
        uint256 price = WaterfallMath.tranchePrice(state.accountedAssets, shares);
        state.entryPriceWad = price;
        if (refreshExitPrice) state.exitPriceWad = price;
        state.lastPriceUpdate = uint64(block.timestamp);
        emit TranchePriceUpdated(
            Tranche(id), state.entryPriceWad, state.exitPriceWad, state.accountedAssets, shares
        );
    }

    function _refreshLossWindowPrices(uint256 residualBefore) internal {
        uint8 seniorId = uint8(Tranche.Senior);
        uint8 mezzanineId = uint8(Tranche.Mezzanine);
        uint8 juniorId = uint8(Tranche.Junior);

        _refreshBookPrice(seniorId, false);
        _refreshBookPrice(mezzanineId, false);
        _refreshBookPrice(juniorId, true);

        _states[seniorId].exitPriceWad = WaterfallMath.protectedSeniorPrice(
            _states[seniorId].accountedAssets,
            _totalShares(seniorId),
            residualBefore,
            SENIOR_PROTECTION_BPS
        );

        _states[mezzanineId].exitPriceWad = WaterfallMath.protectedMezzaninePrice(
            _states[mezzanineId].accountedAssets,
            _totalShares(mezzanineId),
            _states[juniorId].accountedAssets,
            MEZZANINE_PROTECTION_BPS
        );

        _states[seniorId].lastPriceUpdate = uint64(block.timestamp);
        _states[mezzanineId].lastPriceUpdate = uint64(block.timestamp);
    }

    function _settleLossReport(uint256 reportId) internal {
        LossReport storage report = _lossReports[reportId];
        if (report.status == LossReportStatus.None) revert Arcadia__LossReportNotFound(reportId);
        if (report.status != LossReportStatus.Pending) {
            revert Arcadia__LossReportNotPending(reportId);
        }
        if (openLossReportId != reportId) revert Arcadia__LossReportNotPending(reportId);

        sharedResidualValue = report.residualAfter;
        report.status = LossReportStatus.Settled;
        openLossReportId = 0;
        _refreshAllBookPrices();

        emit LossReportSettled(reportId, report.residualAfter);
    }

    function _syncResidualWhenSettled() internal {
        if (openLossReportId == 0) {
            sharedResidualValue = _subordinatedAssets();
        }
    }

    function _subordinatedAssets() internal view returns (uint256) {
        return _states[uint8(Tranche.Mezzanine)].accountedAssets
            + _states[uint8(Tranche.Junior)].accountedAssets;
    }

    function _liquidationPrice(uint8 id) internal view returns (uint256) {
        return WaterfallMath.liquidationPrice(_states[id].accountedAssets, _totalShares(id));
    }
}
