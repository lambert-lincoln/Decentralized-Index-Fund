// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    /// @notice decimal value
    /// @notice Wrapped Ether (WETC) has 18 decimals whereas Wrapped Bitcoin (WBTC) has 8 decimals in the mainnet
    /// @dev decimals should be in the constructor
    uint8 public immutable i_decimals;

    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance,
        uint8 _decimals
    ) payable ERC20(name, symbol) {
        _mint(initialAccount, initialBalance);
        i_decimals = _decimals;
    }

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) public {
        _burn(account, amount);
    }

    function transferInternal(address from, address to, uint256 value) public {
        _transfer(from, to, value);
    }

    function approveInternal(address owner, address spender, uint256 value) public {
        _approve(owner, spender, value);
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }
}
