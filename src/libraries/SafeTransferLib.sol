// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Arcadia__TransferFailed } from "../errors/ArcadiaErrors.sol";

/// @notice Minimal ERC-20 safe transfer helpers that accept optional boolean returns.
library SafeTransferLib {
    function safeTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert Arcadia__TransferFailed();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert Arcadia__TransferFailed();
        }
    }

    function safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x095ea7b3, spender, amount));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert Arcadia__TransferFailed();
        }
    }
}
