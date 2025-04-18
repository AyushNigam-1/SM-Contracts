// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract MealDonationContract {
    address public owner;
    IERC20 public token; // RW-TMCG or other ERC20
    address public donationReceiver;

    struct MealDonation {
        address donor;
        uint256 amount;
        uint256 meals;
        uint256 timestamp;
    }

    MealDonation[] public mealDonations;
    mapping(address => uint256) public totalMealsByDonor;
    uint256 public totalMealsDonated;
    uint256 public tokensPerMeal = 10 * 1e18; // Example: 10 RW-TMCG per meal

    event MealDonated(
        address indexed donor,
        uint256 amount,
        uint256 meals,
        uint256 timestamp
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _tokenAddress, address _donationReceiver) {
        owner = msg.sender;
        token = IERC20(_tokenAddress);
        donationReceiver = _donationReceiver;
    }

    function donateMeals(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        bool success = token.transferFrom(msg.sender, donationReceiver, amount);
        require(success, "Token transfer failed");

        uint256 meals = amount / tokensPerMeal;

        mealDonations.push(
            MealDonation(msg.sender, amount, meals, block.timestamp)
        );
        totalMealsByDonor[msg.sender] += meals;
        totalMealsDonated += meals;

        emit MealDonated(msg.sender, amount, meals, block.timestamp);
    }

    function setTokensPerMeal(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Invalid rate");
        tokensPerMeal = newRate;
    }

    function setDonationReceiver(address newReceiver) external onlyOwner {
        require(newReceiver != address(0), "Invalid address");
        donationReceiver = newReceiver;
    }

    function getDonationCount() external view returns (uint256) {
        return mealDonations.length;
    }

    function getMealDonation(
        uint256 index
    )
        external
        view
        returns (
            address donor,
            uint256 amount,
            uint256 meals,
            uint256 timestamp
        )
    {
        require(index < mealDonations.length, "Invalid index");
        MealDonation memory d = mealDonations[index];
        return (d.donor, d.amount, d.meals, d.timestamp);
    }
}
