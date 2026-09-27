// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.18;
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author Koushik Rawal
 * @notice This is cross-chain rebase token that incentivise users for depositing into the vault ad gain interest in rewards .
 * @notice The global interest rate of smart contract can only decrease
 * @notice Each user has their own interest rate  which is global interest rate
 */
contract RebaseToken is ERC20, AccessControl, Ownable {
    //////////////
    ////Errors////
    //////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    //////////////
    ////state variables////
    //////////////
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimeStamp;
    uint256 private constant PRECESION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    //////////////
    ////Events////
    //////////////
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        // This function is from AccessControl library which gives action to specific contract
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    //////////////
    ////External and public functions ////
    //////////////

    /**
     * @notice Sets the interest rate of the contract
     * @param _newInterestRate  the new interest rate to set
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // The onlyOwner modifier is from ownable contract
    // set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(s_interestRate);
    }

    /**
     * @notice Mint the tokens for a user when user deposits into the vault
     * @param _to The address of user to whom the tokens are going to be minted .
     * @param _amount Amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate; // we are keeping the snapshot  of the interest rate of the user
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from); // before burning we mint the users any interest accrued ...
        _burn(_from, _amount);
    }

    /**
     * It is helper function
     * @notice calaculates the total principal  balance of user including interest if any accumulated  since the last update.
     * @param _user The users address to query to get total balance
     *
     * This just calculates the total balance with any interest accrued since any last intereaction , but the actual minting of the accrued interest tokens are minted in the _mintAccruedInterest function
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principal balance of the user (the number of tokens that have been minted to the user)
        // multiply the principal balance by the interest rate of the user
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECESION_FACTOR;
    }

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient); // this for if a recipient already has deposited some amount in to the protocol then first the interest rate of tokens will be minted in his balance actually , because later we will update the interest rate of the recipient .
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            // this checks that if a user havent deposited any balance into the protocol or have balance = 0 then we inherit the interest rate  of the sender
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     *
     * @notice Transfers tokens from one user to another user
     *
     * @param _sender  The user(sender) who is sending his own tokens  .
     * @param _recipient  The user which receives the transferred tokens from the sender
     * @param _amount  The amount of tokems to be transfered .
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient); // this for if a recipient already has deposited some amount in to the protocol then first the interest rate of tokens will be minted in his balance actually , because later we will update the interest rate of the recipient .
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            // this checks that if a user havent deposited any balance into the protocol or have balance = 0 then we update the interest rate  of the recipient
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest thats has accumulated since the last update
        // this is gowing to be linear growth with time
        // 1.calculate the time since the last update
        // 2.calculate the amount of linear growth
        // (principal amaount) + (principal amount * user interest rate  * time elapsed)
        // Ex :
        // deposit : 10 tokens
        // interest rate 0.5 tokens per second
        // time elapsed : 2 seconds
        // 10 + (10 * 0.5 * 2)
        // 10 + 10
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimeStamp[_user];
        linearInterest = PRECESION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     *
     * @notice this function is used to mint the interest number of  tokens to  a user before minting new tokens
     * @param _user - the user to whom the interest is going to be minted and who is minting again rather than he minted before
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user .
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest  -> from balanceOf
        uint256 currentPrincipleBalanceWithInterest = balanceOf(_user);
        // calculate the number of tokens that need to be minted actually to the user  -> (2)-(1)
        uint256 balanceIncrease = currentPrincipleBalanceWithInterest - previousPrincipleBalance;
        // call _mint to mint the remaining tokens to the user .
        // set the users last updated timestamp.
        s_userLastUpdatedTimeStamp[_user] = block.timestamp; // keeping the snapshot of the time of last update
        _mint(_user, balanceIncrease);
    }

    ////////////////////////
    ////Getter functions////
    ////////////////////////

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    function getUserPrincipleBalance(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function getProtocolsCurrentInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    function getMintAndBurnRole() external view returns (bytes32) {
        return MINT_AND_BURN_ROLE;
    }
}
