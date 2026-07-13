// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ArcadiaRoles } from "../access/ArcadiaRoles.sol";
import {
    Arcadia__InsufficientShares,
    Arcadia__InvalidTranche,
    Arcadia__Unauthorized,
    Arcadia__ZeroAddress,
    Arcadia__ZeroAmount
} from "../errors/ArcadiaErrors.sol";
import { ArcadiaTypes, Tranche } from "../types/ArcadiaTypes.sol";

/// @notice Optional delayed-redemption queue for frontends and guarded deployments.
contract RedemptionQueue is ArcadiaRoles {
    struct RedemptionRequest {
        uint256 id;
        Tranche tranche;
        address owner;
        address receiver;
        uint256 shares;
        uint256 minAssets;
        uint64 requestedAt;
        uint64 executableAt;
        bool claimed;
        bool cancelled;
    }

    address public immutable vault;
    uint64 public defaultDelay;
    uint256 public nextRequestId = 1;
    uint256 public pendingShares;
    uint256 public claimedRequests;
    uint256 public cancelledRequests;

    mapping(uint256 => RedemptionRequest) private _requests;
    mapping(address => uint256[]) private _ownerRequests;
    mapping(uint8 => uint256) public tranchePendingShares;

    event RequestCreated(
        uint256 indexed id,
        Tranche indexed tranche,
        address indexed owner,
        address receiver,
        uint256 shares,
        uint256 minAssets,
        uint64 executableAt
    );
    event RequestCancelled(uint256 indexed id, address indexed owner);
    event RequestClaimed(uint256 indexed id, address indexed executor, uint256 assets);
    event DefaultDelayUpdated(uint64 previousDelay, uint64 newDelay);

    modifier onlyVault() {
        if (msg.sender != vault) revert Arcadia__Unauthorized(bytes32("VAULT"), msg.sender);
        _;
    }

    constructor(address admin, address vault_, uint64 defaultDelay_) ArcadiaRoles(admin) {
        if (vault_ == address(0)) revert Arcadia__ZeroAddress();
        vault = vault_;
        defaultDelay = defaultDelay_;
        _grantInitialRole(ArcadiaTypes.GUARDIAN_ROLE, admin);
    }

    function setDefaultDelay(uint64 newDelay) external onlyRole(ArcadiaTypes.GUARDIAN_ROLE) {
        uint64 previous = defaultDelay;
        defaultDelay = newDelay;
        emit DefaultDelayUpdated(previous, newDelay);
    }

    function createRequest(
        Tranche tranche,
        address owner,
        address receiver,
        uint256 shares,
        uint256 minAssets,
        uint64 customDelay
    ) external returns (uint256 id) {
        if (owner == address(0) || receiver == address(0)) {
            revert Arcadia__ZeroAddress();
        }
        if (shares == 0) revert Arcadia__ZeroAmount();
        uint8 trancheId = uint8(tranche);
        if (trancheId > uint8(Tranche.Junior)) revert Arcadia__InvalidTranche(trancheId);

        uint64 delay = customDelay == 0 ? defaultDelay : customDelay;
        id = nextRequestId++;
        uint64 executableAt = uint64(block.timestamp + delay);
        _requests[id] = RedemptionRequest({
            id: id,
            tranche: tranche,
            owner: owner,
            receiver: receiver,
            shares: shares,
            minAssets: minAssets,
            requestedAt: uint64(block.timestamp),
            executableAt: executableAt,
            claimed: false,
            cancelled: false
        });
        _ownerRequests[owner].push(id);
        pendingShares += shares;
        tranchePendingShares[trancheId] += shares;

        emit RequestCreated(id, tranche, owner, receiver, shares, minAssets, executableAt);
    }

    function cancelRequest(uint256 id) external {
        RedemptionRequest storage request = _activeRequest(id);
        if (msg.sender != request.owner && !hasRole(ArcadiaTypes.GUARDIAN_ROLE, msg.sender)) {
            revert Arcadia__Unauthorized(bytes32("REQUEST_OWNER"), msg.sender);
        }

        request.cancelled = true;
        _releasePending(request.tranche, request.shares);
        cancelledRequests += 1;
        emit RequestCancelled(id, request.owner);
    }

    function markClaimed(uint256 id, uint256 assets) external onlyVault {
        RedemptionRequest storage request = _activeRequest(id);
        request.claimed = true;
        _releasePending(request.tranche, request.shares);
        claimedRequests += 1;
        emit RequestClaimed(id, msg.sender, assets);
    }

    function request(uint256 id) external view returns (RedemptionRequest memory) {
        return _requests[id];
    }

    function ownerRequests(address owner) external view returns (uint256[] memory) {
        return _ownerRequests[owner];
    }

    function ready(uint256 id) external view returns (bool) {
        RedemptionRequest memory request_ = _requests[id];
        return request_.id != 0 && !request_.claimed && !request_.cancelled
            && block.timestamp >= request_.executableAt;
    }

    function claimableShares(address owner, Tranche tranche)
        external
        view
        returns (uint256 shares)
    {
        uint256[] memory ids = _ownerRequests[owner];
        for (uint256 i; i < ids.length; ++i) {
            RedemptionRequest memory request_ = _requests[ids[i]];
            if (
                request_.tranche == tranche && !request_.claimed && !request_.cancelled
                    && block.timestamp >= request_.executableAt
            ) {
                shares += request_.shares;
            }
        }
    }

    function pendingRequestCount(address owner) external view returns (uint256 count) {
        uint256[] memory ids = _ownerRequests[owner];
        for (uint256 i; i < ids.length; ++i) {
            RedemptionRequest memory request_ = _requests[ids[i]];
            if (!request_.claimed && !request_.cancelled) count += 1;
        }
    }

    function _activeRequest(uint256 id) internal view returns (RedemptionRequest storage request_) {
        request_ = _requests[id];
        if (request_.id == 0) revert Arcadia__ZeroAmount();
        if (request_.claimed || request_.cancelled) revert Arcadia__InsufficientShares(0, 0);
    }

    function _releasePending(Tranche tranche, uint256 shares) internal {
        pendingShares -= shares;
        tranchePendingShares[uint8(tranche)] -= shares;
    }
}
