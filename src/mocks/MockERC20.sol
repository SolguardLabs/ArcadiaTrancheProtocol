// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";
import {
    Arcadia__InsufficientAllowance,
    Arcadia__InsufficientShares,
    Arcadia__Unauthorized,
    Arcadia__ZeroAddress
} from "../errors/ArcadiaErrors.sol";

/// @notice Capped ERC-20 used by local deployments and tests.
contract MockERC20 is IERC20 {
    string public override name;
    string public override symbol;
    uint8 public immutable override decimals;
    address public admin;
    uint256 public cap;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event CapUpdated(uint256 previousCap, uint256 newCap);

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Arcadia__Unauthorized(bytes32("ADMIN"), msg.sender);
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address admin_,
        uint256 cap_
    ) {
        if (admin_ == address(0)) revert Arcadia__ZeroAddress();
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        admin = admin_;
        cap = cap_;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert Arcadia__ZeroAddress();
        address previous = admin;
        admin = newAdmin;
        emit AdminTransferred(previous, newAdmin);
    }

    function setCap(uint256 newCap) external onlyAdmin {
        if (newCap != 0 && newCap < totalSupply) {
            revert Arcadia__InsufficientShares(totalSupply, newCap);
        }
        uint256 previous = cap;
        cap = newCap;
        emit CapUpdated(previous, newCap);
    }

    function mint(address account, uint256 amount) external onlyAdmin {
        if (account == address(0)) revert Arcadia__ZeroAddress();
        uint256 newSupply = totalSupply + amount;
        if (cap != 0 && newSupply > cap) revert Arcadia__InsufficientShares(newSupply, cap);
        totalSupply = newSupply;
        unchecked {
            balanceOf[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function burn(address account, uint256 amount) external onlyAdmin {
        _burn(account, amount);
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        if (spender == address(0)) revert Arcadia__ZeroAddress();
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount)
        external
        override
        returns (bool)
    {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert Arcadia__InsufficientAllowance(amount, currentAllowance);
            }
            unchecked {
                allowance[from][msg.sender] = currentAllowance - amount;
            }
            emit Approval(from, msg.sender, currentAllowance - amount);
        }
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert Arcadia__ZeroAddress();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < amount) revert Arcadia__InsufficientShares(amount, fromBalance);
        unchecked {
            balanceOf[from] = fromBalance - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }

    function _burn(address account, uint256 amount) internal {
        uint256 accountBalance = balanceOf[account];
        if (accountBalance < amount) revert Arcadia__InsufficientShares(amount, accountBalance);
        unchecked {
            balanceOf[account] = accountBalance - amount;
            totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
    }
}
