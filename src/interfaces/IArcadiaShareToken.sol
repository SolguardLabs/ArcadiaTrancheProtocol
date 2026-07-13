// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "./IERC20.sol";

interface IArcadiaShareToken is IERC20 {
    function vault() external view returns (address);
    function mint(address account, uint256 amount) external;
    function burnFrom(address account, uint256 amount) external;
    function spendAllowance(address owner, address spender, uint256 amount) external;
}
