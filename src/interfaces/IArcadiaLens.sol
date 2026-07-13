// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { ProtocolSnapshot, Tranche, TrancheSnapshot } from "../types/ArcadiaTypes.sol";

interface IArcadiaLens {
    function protocolSnapshot() external view returns (ProtocolSnapshot memory);
    function trancheSnapshot(Tranche tranche) external view returns (TrancheSnapshot memory);
    function allTranches() external view returns (TrancheSnapshot[3] memory);
    function accountValue(address account) external view returns (uint256);
}
