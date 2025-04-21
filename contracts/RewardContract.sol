// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract RewardContract is AccessControl, ReentrancyGuard {
    bytes32 public constant REWARD_MANAGER_ROLE =
        keccak256("REWARD_MANAGER_ROLE");

    IERC20 public immutable rewardToken;
    uint256 public rewardRate; // Example: 5 means 5% reward

    mapping(address => uint256) public rewardsGiven;

    event RewardIssued(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate);

    constructor(address _tokenAddress, uint256 _rewardRate) {
        require(_tokenAddress != address(0), "Invalid token");
        require(_rewardRate > 0, "Invalid reward rate");

        rewardToken = IERC20(_tokenAddress);
        rewardRate = _rewardRate;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARD_MANAGER_ROLE, msg.sender);
    }

    function issueReward(
        address user,
        uint256 baseAmount
    ) external onlyRole(REWARD_MANAGER_ROLE) nonReentrant {
        require(user != address(0), "Invalid user");
        require(baseAmount > 0, "Base amount must be > 0");

        uint256 reward = (baseAmount * rewardRate) / 100;
        require(
            rewardToken.balanceOf(address(this)) >= reward,
            "Insufficient contract balance"
        );

        rewardsGiven[user] += reward;
        bool success = rewardToken.transfer(user, reward);
        require(success, "Reward transfer failed");

        emit RewardIssued(user, reward);
    }

    function setRewardRate(
        uint256 newRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRate > 0, "Invalid rate");
        rewardRate = newRate;
        emit RewardRateUpdated(newRate);
    }
}
