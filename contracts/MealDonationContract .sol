// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MealDonationContract is AccessControl, ReentrancyGuard {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    IERC20 public token;
    address public donationReceiver;
    uint256 public tokensPerMeal = 10 * 1e18;

    struct MealDonation {
        address donor;
        uint256 amount;
        uint256 meals;
        uint256 timestamp;
    }

    mapping(uint256 => MealDonation) public donations;
    mapping(address => uint256) public totalMealsByDonor;
    uint256 public totalMealsDonated;
    uint256 public donationCount;

    event MealDonated(
        address indexed donor,
        uint256 amount,
        uint256 meals,
        uint256 timestamp
    );
    event TokensPerMealUpdated(uint256 newRate);
    event DonationReceiverUpdated(address newReceiver);

    constructor(address _token, address _receiver) {
        require(_token != address(0), "Invalid token");
        require(_receiver != address(0), "Invalid receiver");

        token = IERC20(_token);
        donationReceiver = _receiver;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    function donateMeals(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");
        require(
            token.transferFrom(msg.sender, donationReceiver, amount),
            "Token transfer failed"
        );

        uint256 meals = amount / tokensPerMeal;

        donations[donationCount] = MealDonation(
            msg.sender,
            amount,
            meals,
            block.timestamp
        );
        totalMealsByDonor[msg.sender] += meals;
        totalMealsDonated += meals;
        emit MealDonated(msg.sender, amount, meals, block.timestamp);
        donationCount++;
    }

    function setTokensPerMeal(uint256 newRate) external onlyRole(OWNER_ROLE) {
        require(newRate > 0, "Invalid rate");
        tokensPerMeal = newRate;
        emit TokensPerMealUpdated(newRate);
    }

    function setDonationReceiver(
        address newReceiver
    ) external onlyRole(OWNER_ROLE) {
        require(newReceiver != address(0), "Invalid receiver");
        donationReceiver = newReceiver;
        emit DonationReceiverUpdated(newReceiver);
    }

    function getDonation(
        uint256 index
    ) external view returns (MealDonation memory) {
        require(index < donationCount, "Invalid index");
        return donations[index];
    }

    function getDonationCount() external view returns (uint256) {
        return donationCount;
    }

    function getTotalMealsBy(address donor) external view returns (uint256) {
        return totalMealsByDonor[donor];
    }
}
