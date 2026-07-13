// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20 } from "../interfaces/IERC20.sol";
import {
    Arcadia__InsufficientAllowance,
    Arcadia__InsufficientShares,
    Arcadia__Unauthorized,
    Arcadia__ZeroAddress
} from "../errors/ArcadiaErrors.sol";

/// @notice ERC-20 compatible receipt token minted and burned exclusively by the vault.
contract TrancheShareToken is IERC20 {
    string public override name;
    string public override symbol;
    uint8 public immutable override decimals;
    address public immutable vault;

    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    modifier onlyVault() {
        if (msg.sender != vault) revert Arcadia__Unauthorized(bytes32("VAULT"), msg.sender);
        _;
    }

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address vault_) {
        if (vault_ == address(0)) revert Arcadia__ZeroAddress();
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        vault = vault_;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
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
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address account, uint256 amount) external onlyVault {
        if (account == address(0)) revert Arcadia__ZeroAddress();
        totalSupply += amount;
        unchecked {
            balanceOf[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }

    function burnFrom(address account, uint256 amount) external onlyVault {
        _burn(account, amount);
    }

    function spendAllowance(address owner, address spender, uint256 amount) external onlyVault {
        _spendAllowance(owner, spender, amount);
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

    function _approve(address owner, address spender, uint256 amount) internal {
        if (owner == address(0) || spender == address(0)) revert Arcadia__ZeroAddress();
        allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance[owner][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) {
                revert Arcadia__InsufficientAllowance(amount, currentAllowance);
            }
            unchecked {
                allowance[owner][spender] = currentAllowance - amount;
            }
            emit Approval(owner, spender, currentAllowance - amount);
        }
    }
}
