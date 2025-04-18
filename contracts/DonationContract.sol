// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

contract EDonations {
    address public owner;
    IERC20 public token; // RW-TMCG or other ERC20 token

    struct Donation {
        address donor;
        address receiver;
        uint256 amount;
        string campaign;
        uint256 timestamp;
    }

    Donation[] public donations;
    mapping(address => uint256) public donorTotal;

    mapping(string => bool) public validCampaigns;
    mapping(string => address) public campaignReceivers;

    event DonationReceived(
        address indexed donor,
        address indexed receiver,
        uint256 amount,
        string campaign,
        uint256 timestamp
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _tokenAddress) {
        owner = msg.sender;
        token = IERC20(_tokenAddress);
    }

    function addCampaign(
        string memory name,
        address receiver
    ) external onlyOwner {
        require(bytes(name).length > 0, "Empty campaign name");
        require(receiver != address(0), "Invalid receiver");
        validCampaigns[name] = true;
        campaignReceivers[name] = receiver;
    }

    function removeCampaign(string memory name) external onlyOwner {
        validCampaigns[name] = false;
        campaignReceivers[name] = address(0);
    }

    function isCampaignValid(string memory name) external view returns (bool) {
        return validCampaigns[name];
    }

    function donate(string memory campaign, uint256 amount) external {
        require(validCampaigns[campaign], "Invalid campaign");
        require(amount > 0, "Amount must be > 0");

        address receiver = campaignReceivers[campaign];
        require(receiver != address(0), "No receiver set for campaign");

        bool success = token.transferFrom(msg.sender, receiver, amount);
        require(success, "Token transfer failed");

        donations.push(
            Donation(msg.sender, receiver, amount, campaign, block.timestamp)
        );
        donorTotal[msg.sender] += amount;

        emit DonationReceived(
            msg.sender,
            receiver,
            amount,
            campaign,
            block.timestamp
        );
    }

    function getDonation(
        uint256 index
    )
        external
        view
        returns (
            address donor,
            address receiver,
            uint256 amount,
            string memory campaign,
            uint256 timestamp
        )
    {
        require(index < donations.length, "Invalid index");
        Donation memory d = donations[index];
        return (d.donor, d.receiver, d.amount, d.campaign, d.timestamp);
    }

    function getDonationCount() external view returns (uint256) {
        return donations.length;
    }

    function getTotalDonatedBy(address donor) external view returns (uint256) {
        return donorTotal[donor];
    }

    function updateTokenAddress(address newToken) external onlyOwner {
        require(newToken != address(0), "Invalid token");
        token = IERC20(newToken);
    }
}
