// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
* @title RebaseToken
* @author Tebbo
* @notice This is a crosschain rebase token that incentivises users to deposit into a vault
* @notice The interest in the smartcontract can only decrease
* @notice Each user will have their own interest rate which will be the global interest rate at the time of depositing.
*/

contract RebaseToken is ERC20, Ownable(msg.sender), AccessControl {
    // ************************************
    // **  Errors
    // ************************************

    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private constant PRECISION_FACTOR = 1e18; // To avoid precision issues with interest rate calculations
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    // *************************************
    // **  Events
    // *************************************

    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {}

    function grantBurnAdMintRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
    * @notice Set the new interest rate
    * @param _newInterestRate The new interest rate to set
    * @dev The interest rate can only decrease
    * @dev Emits an InterestRateSet event
    */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user
     * @param _user The address of the user
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /// @notice Mints new tokens for a given address. Called when a user either deposits or bridges tokens to this chain.
    /// @param _to The address to mint the tokens to.
    /// @param _value The number of tokens to mint.
    /// @param _userInterestRate The interest rate of the user. This is either the contract interest rate if the user is depositing or the user's interest rate from the source token if the user is bridging.
    /// @dev this function increases the total supply.
    function mint(address _to, uint256 _value, uint256 _userInterestRate) public onlyRole(MINT_AND_BURN_ROLE) {
        // Mints any existing interest that has accrued since the last time the user's balance was updated.
        _mintAccruedInterest(_to);
        // Sets the users interest rate to either their bridged value if they are bridging or to the current interest rate if they are depositing.
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _value);
    }

    /**
     * @notice Burn tokens from a user
     * @param _from The address of the user to burn tokens from
     * @param _amount The amount of tokens to burn
     * @dev This function burns tokens from a user and mints the accrued interest for the user
     * @dev It updates the user's last updated timestamp to the current block timestamp
     * @dev The user's interest rate is set to the current global interest rate
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // if (_amount == type(uint256).max) {
        //     _amount = balanceOf(_from);
        // }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function _calculatedUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
        return linearInterest;
    }

    /**
     * @notice Calculate the accumulated interest for a user since their last update
     * @param _user The address of the user
     * @return The accumulated interest for the user since their last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        return super.balanceOf(_user) * _calculatedUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return Whether the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     *
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
    * @notice Mint the accrued interest for a user
    * @param _user The address of the user
    * @dev This function is called when a user mints tokens or deposits into the vault
    * @dev It calculates the interest accrued since the last update and mints the corresponding amount
    * @dev The user's last updated timestamp is also updated to the current block timestamp
    * @dev The user's interest rate is set to the current global interest rate
    */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    //*********************************************
    // **  Getter functions
    // *********************************************

    /**
    * @notice get the interest rate for a user
    * @param _user The address of the user
    * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    /**
    * @notice Get the interest rate that is currently set for the contract. Any future depositors will receive
    */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
