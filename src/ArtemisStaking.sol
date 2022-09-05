//SPDX-License-Identifier-MIT

/**
 * Prompt
 *
 * COMPLETED
 * Implement a contract that allows anyone to deposit
 * a predefined token and earn more of that same token over time, for as long as it
 * remains deposited. At the time of deposit the user should receive a “receipt”
 * token that represents their claim on the deposited amount plus accrued rewards.
 *
 * COMPLETED
 * The depositor can check their balance
 *
 * COMPLETED
 * And exchange their receipt tokens for the
 * deposited tokens plus the accrued rewards at any given time.
 *
 * COMPLETED
 * Multiple users should be able to stake their tokens and claim their rewards.
 *
 */

pragma solidity 0.8.15;

import {IArtemisERC20} from "../src/interfaces/IArtemisERC20.sol";
import {ERC20} from "openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ArtemisStaking is ReentrancyGuard {
    /*///////////////////////////////////////////////////////////////
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public balances;

    /*///////////////////////////////////////////////////////////////
                        STATE VARIABLES 
    //////////////////////////////////////////////////////////////*/

    uint256 public totalSupply;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 30 days;
    address public owner;
    IArtemisERC20 public stakingToken;

    /*///////////////////////////////////////////////////////////////
                             ERRORS 
    //////////////////////////////////////////////////////////////*/

    error TransferFailed();
    error NotOwner();

    /*///////////////////////////////////////////////////////////////
                             EVENTS 
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed _caller, uint256 _amount);
    event Withdraw(address indexed _caller, uint256 _amount);
    event RewardDeposit(address indexed _caller, uint256 _rewards);
    event RewardsClaimed(address indexed _account, uint256 _reward);

    constructor(address _stakingToken, address _owner) {
        stakingToken = IArtemisERC20(_stakingToken);
        owner = _owner;
    }

    /*///////////////////////////////////////////////////////////////
                             REWARD LOGIC 
    //////////////////////////////////////////////////////////////*/

    function issuanceRate(uint256 _rewards)
        public
        nonReentrant
        updateReward(address(0))
    {
        if (msg.sender != owner) {
            revert NotOwner();
        }
        require(_rewards > 0, "Rewards must be > 0");
        require(totalSupply != 0, "Supply must be > 0");
        if (block.timestamp >= periodFinish) {
            rewardRate = _rewards / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (_rewards + leftover) / rewardsDuration;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        bool success = stakingToken.transferFrom(
            msg.sender,
            address(this),
            _rewards
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;

        if (!success) revert TransferFailed();

        emit RewardDeposit(msg.sender, _rewards);
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored +
            (((lastTimeRewardApplicable() - lastUpdateTime) *
                rewardRate *
                1e18) / totalSupply);
    }

    function earned(address account) public view returns (uint256) {
        return
            ((balances[account] *
                (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) +
            rewards[account];
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate * rewardsDuration;
    }

    /*///////////////////////////////////////////////////////////////
                             USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 _amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(stakingToken.balanceOf(msg.sender) > 0, "Cannot deposit 0");
        balances[msg.sender] += _amount;
        totalSupply += _amount;
        bool success = stakingToken.transferFrom(
            msg.sender,
            address(this),
            _amount
        );
        if (!success) revert TransferFailed();
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice user withdraw function allowing them to receive their staked tokens and rewards
     * @param _amount the amount of staked tokens they would like to withdraw
     * @dev need to add reentrancy guard as claim rewards has to go before state changes
     * or an error will ne thrown due to balances being used in both places.
     */

    function withdraw(uint256 _amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(_amount > 0, "Cannot Withdraw 0");
        require(_amount <= balances[msg.sender], "Insufficent Balance");
        claimReward(_amount, msg.sender);
        balances[msg.sender] = _amount;
        totalSupply -= _amount;
        bool success = stakingToken.transfer(msg.sender, _amount);
        if (!success) revert TransferFailed();
        emit Withdraw(msg.sender, _amount);
    }

    /*///////////////////////////////////////////////////////////////
                             INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function claimReward(uint256 amount, address _account) internal {
        uint256 reward = (rewards[_account] * amount) / balances[_account];
        rewards[_account] -= reward;
        emit RewardsClaimed(_account, reward);
        bool success = stakingToken.transfer(_account, reward);
        if (!success) {
            revert TransferFailed();
        }
    }

    /*///////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    function checkRewards(address _staker) public view returns (uint256) {
        return earned(_staker);
    }

    function balance(address _staker) public view returns (uint256) {
        return balances[_staker];
    }

    /*///////////////////////////////////////////////////////////////
                        MODIFIER FUNCTIONS 
    //////////////////////////////////////////////////////////////*/

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }
}
