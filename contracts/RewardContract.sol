// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IKnowledgeToken {
    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract RewardContract is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant REWARD_MANAGER_ROLE =
        keccak256("REWARD_MANAGER_ROLE");

    IKnowledgeToken public immutable rewardToken;

    event RewardIssued(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "Invalid token address");

        rewardToken = IKnowledgeToken(tokenAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARD_MANAGER_ROLE, msg.sender);
    }

    function issueReward(
        address user,
        uint256 amount
    ) external onlyRole(REWARD_MANAGER_ROLE) nonReentrant whenNotPaused {
        require(user != address(0), "Invalid user address");
        require(amount > 0, "Reward must be greater than zero");
        require(
            rewardToken.balanceOf(address(this)) >= amount,
            "Insufficient contract balance"
        );

        bool success = rewardToken.transfer(user, amount);
        require(success, "Reward transfer failed");

        emit RewardIssued(user, amount);
    }

    function withdrawTokens(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(to != address(0), "Invalid recipient address");
        require(amount > 0, "Withdraw amount must be greater than zero");
        require(
            rewardToken.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );

        bool success = rewardToken.transfer(to, amount);
        require(success, "Withdraw failed");

        emit TokensWithdrawn(to, amount);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    receive() external payable {
        revert("Native payments not supported");
    }
}
