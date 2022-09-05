//SPDX-License-Identifier-MIT

/**
 * Prompt
 *
 * COMPLETED
 * Implement an escrow contract. This contract should be able to hold any amount of a given token sent by a defined set of participants (senders).
 *
 *COMPLETED
 * After a predefined time window a different set of participants (receivers) are able to withdraw the funds in a pro rata fashion based on predefined weights.
 *
 * COMPLETED
 * Funds must not be withdrawn until the expiry time was reached. Any sender can file for a dispute.
 */

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ArtemisEscrow is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*///////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    bool public underDispute;
    address[] public tokens;
    address public owner;
    uint256 public withdrawTime;

    /*///////////////////////////////////////////////////////////////
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => uint256) public balances;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public payout;
    mapping(address => bool) public receivers;
    mapping(address => uint256) public userBalances;
    mapping(address => bool) public whitelistedDepositors;
    mapping(address => bool) public whitelistedTokens;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed _caller,
        address indexed _token,
        uint256 _amount
    );
    event Withdraw(
        address indexed _caller,
        IERC20 indexed _token,
        uint256 _amount
    );

    /*///////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) {
        owner = _owner;
    }

    /*///////////////////////////////////////////////////////////////
                             USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice allows for whitelisted individuals to deposit into the escrow contract
     * @param _token the address of the token being deposited
     * @param _amount the amount of tokens to be deposited
     * @dev limit time slot when deposits are available for accounting during withdraws
     */

    function deposit(address _token, uint256 _amount)
        public
        whenNotPaused
        onlywhitelistedDepositors(msg.sender, _token)
    {
        require(_amount > 0, "Cannot deposit 0");
        require(underDispute != true, "Under Dispute");
        balances[_token] += _amount;
        userBalances[msg.sender] += _amount;
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        emit Deposit(msg.sender, _token, _amount);
    }

    /**
     * @notice allows for whitelisted addresses to withdraw tokens pro rata
     * @param _to address recieving the tokens
     * @dev before withdraws begin deposits must be locked because the balances mapping is
     * used for accounting. If you do not have a locked balance indiviudals will not get the
     * amount that they are owed.
     */

    function withdraw(address _to)
        public
        whenPaused
        nonReentrant
        onlyReceivers(msg.sender)
    {
        require(block.timestamp > withdrawTime, "Cannot withdraw yet");
        require(underDispute != true, "Under Dispute");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 assetBalance = (balances[address(token)] *
                payout[msg.sender]) / 1000;
            if (assetBalance > 0) {
                token.transfer(_to, assetBalance);
            }
            emit Withdraw(msg.sender, token, assetBalance);
        }
    }

    ///@notice allows depositors to dispute the deal prior to users being able to withdraw
    function dispute() external {
        require(whitelistedDepositors[msg.sender] == true, "Not Depositor");
        require(block.timestamp < withdrawTime);
        underDispute = true;
    }

    /**
     * @notice if a agreement is made depositors can "settle" the dispute
     * or if a resolution is not agreed upon depositors will receive their
     * money back
     * @param _settlement true or false statement based on if there is an agreement
     * @param _token that the depositor entered, needed to get their money back
     */
    function settleDispute(bool _settlement, address _token) external {
        require(whitelistedDepositors[msg.sender] == true);
        if (_settlement == true) {
            underDispute = false;
        } else {
            uint256 amount = userBalances[msg.sender];
            IERC20(_token).safeTransfer(msg.sender, amount);
        }
    }

    /*///////////////////////////////////////////////////////////////
                             OWNER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice whitelisting for whitelistedDepositors
     * @param _participant the address getting whitelisted
     * @param _token the token they will be depositing
     * @dev the token gets added to a dynamic array for the
     * withdraw process.
     */
    function setWhitelistedDepositors(address _participant, address _token)
        public
        onlyOwner
    {
        whitelistedDepositors[_participant] = true;
        if (whitelistedTokens[_token] == false) {
            tokens.push(_token);
            whitelistedTokens[_token] = true;
        }
    }

    ///@notice whitelisting for receivers
    function setReceivers(address _receiver) public onlyOwner {
        receivers[_receiver] = true;
    }

    ///@notice updates mapping for which receivers are able to withdraw what amount
    function setPayout(uint256 _percentage, address _receiver)
        public
        onlyOwner
    {
        require(receivers[_receiver] == true, "not a valid receiver");
        require(_percentage > 0 && _percentage <= 1000);
        payout[_receiver] = _percentage;
    }

    function removeDepositor(address _participant) external onlyOwner {
        delete whitelistedDepositors[_participant];
    }

    function removeReceiver(address _participant) external onlyOwner {
        delete receivers[_participant];
    }

    /**
     * @notice amount of blocks that must pass from current block
     * until users can withdraw
     */

    function wait(uint256 _wait) external onlyOwner {
        withdrawTime = block.timestamp + _wait;
    }

    ///@notice pausing deposits and allowing withdraws
    function pause() external onlyOwner {
        _pause();
    }

    ///@notice unpausing deposits and pausing withdraws
    function unPause() external onlyOwner {
        _unpause();
    }

    ///@notice resets the transaction state and removes tokens from the array
    function resetState() external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            delete tokens[0];
        }
    }

    /*///////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice checks the balance of a speific token
     * @param _token address of the token that is being checked
     */
    function checkBalances(address _token) public view returns (uint256) {
        return balances[_token];
    }

    /*///////////////////////////////////////////////////////////////
                             MODIFIER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier onlywhitelistedDepositors(address _participants, address _token) {
        require(whitelistedDepositors[_participants] == true, "Not depositor");
        require(whitelistedTokens[_token] == true, "Not a depositable token");
        _;
    }
    modifier onlyReceivers(address _participants) {
        require(receivers[_participants] == true, "Not Receiver");
        _;
    }
}
