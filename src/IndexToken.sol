// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title IndexToken
/// @author l@mb
/// @notice The stablecoin which is a decentralized index fund of the top 3 crypto tokens with the largest market cap to date
/*
* Collateral: Exogenous
* Minting: Algorithmic
* Value: [insert here later on]
*/

contract IndexToken is ERC20, Ownable {
    error IndexToken__NotZeroAddress();
    error IndexToken__AmountMustBeMoreThanZero();
    error IndexToken__InsufficientBalanceToBurn();

    constructor(address ownerAddress) ERC20("DeFi Index", "dIDX") Ownable(ownerAddress) {}

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        // reverts if send to empty address
        if (to == address(0)) {
            revert IndexToken__NotZeroAddress();
        }

        // reverts if mintAmonut <= 0
        if (amount <= 0) {
            revert IndexToken__AmountMustBeMoreThanZero();
        }

        super._mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyOwner returns (bool) {
        uint256 balance = balanceOf(from);
        // reverts if burnAmount <= 0
        if (amount <= 0) {
            revert IndexToken__AmountMustBeMoreThanZero();
        }

        // reverts if burnAmount < balanceOf(user)
        if (amount > balance) {
            revert IndexToken__InsufficientBalanceToBurn();
        }

        // reverts is from is zero address
        if (from == address(0)) {
            revert IndexToken__NotZeroAddress();
        }
        super._burn(from, amount);
        return true;
    }
}
