//  SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    ///////////////////
    //// Errors //////
    //////////////////
    error vault__RedeemTransferFailed();

    //////////////
    ////state variables////
    //////////////
    IRebaseToken private immutable i_rebaseToken;

    //////////////
    ////Events////
    //////////////
    event Deposited(address indexed user, uint256 amount, uint256 interestRate);
    event Redeemed(address indexed user, uint256 amount);

    // We need to pass the Token Address to the constructor
    // We need to create a function to deposit where user can deposit money and can get equally token minted (No.oF Balance = No.Of Token)
    // We need to create a function withdraw where user can redeem their balance and but the tokens
    // Create a way to add the rewards to the vault
    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice User can deposit ETH and can mint the tokens  as per the amount
     */
    function deposit() external payable {
        // We need to use the deposited amount to mint the rebase tokens to the user who is calling
        uint256 interestRate = i_rebaseToken.getProtocolsCurrentInterestRate(); // This will sets the interest rate  to the user who is depositing
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposited(msg.sender, msg.value, interestRate);
    }

    /**
     * @notice User can redeem their balance and burn the tokens
     * @param _amount The amount of ETH to be redeem
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. First  burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. Transfer the amount to the user
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert vault__RedeemTransferFailed();
        }
        emit Redeemed(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
