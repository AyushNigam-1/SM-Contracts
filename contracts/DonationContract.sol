// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract EDonations is ReentrancyGuard, AccessControl {
    using Strings for uint256;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    IERC20 public token;

    struct Donation {
        address donor;
        address receiver;
        uint256 amount;
        string campaign;
        uint256 timestamp;
    }

    mapping(uint256 => Donation) public donations;
    uint256 public donationCount;

    mapping(address => uint256) public donorTotal;

    mapping(string => bool) public validCampaigns;
    mapping(string => address) public campaignReceivers;

    uint256 public constant MAX_CAMPAIGN_NAME_LENGTH = 64;

    event DonationReceived(
        address indexed donor,
        address indexed receiver,
        uint256 amount,
        string campaign,
        uint256 timestamp
    );

    event CampaignAdded(string campaign, address receiver);
    event CampaignRemoved(string campaign);
    event TokenWithdrawn(address tokenAddress, address to, uint256 amount);

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        token = IERC20(_tokenAddress);
    }

    modifier onlyCampaign(string memory campaign) {
        require(validCampaigns[campaign], "Campaign not active");
        _;
    }

    function addCampaign(
        string memory name,
        address receiver
    ) external onlyRole(OWNER_ROLE) {
        require(
            bytes(name).length > 0 &&
                bytes(name).length <= MAX_CAMPAIGN_NAME_LENGTH,
            "Invalid campaign name"
        );
        require(receiver != address(0), "Invalid receiver address");
        require(!validCampaigns[name], "Campaign already exists");

        validCampaigns[name] = true;
        campaignReceivers[name] = receiver;
        emit CampaignAdded(name, receiver);
    }

    function removeCampaign(string memory name) external onlyRole(OWNER_ROLE) {
        require(validCampaigns[name], "Campaign does not exist");
        delete validCampaigns[name];
        delete campaignReceivers[name];
        emit CampaignRemoved(name);
    }

    function isCampaignValid(string memory name) external view returns (bool) {
        return validCampaigns[name];
    }

    function donate(
        string calldata campaign,
        uint256 amount
    ) external nonReentrant onlyCampaign(campaign) {
        require(amount > 0, "Donation amount must be greater than zero");

        address receiver = campaignReceivers[campaign];
        require(receiver != address(0), "Campaign receiver missing");

        bool success = token.transferFrom(msg.sender, receiver, amount);
        require(success, "Token transfer failed");

        donations[donationCount] = Donation(
            msg.sender,
            receiver,
            amount,
            campaign,
            block.timestamp
        );

        donorTotal[msg.sender] += amount;

        emit DonationReceived(
            msg.sender,
            receiver,
            amount,
            campaign,
            block.timestamp
        );

        donationCount++;
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
        require(index < donationCount, "Donation index out of bounds");
        Donation memory d = donations[index];
        return (d.donor, d.receiver, d.amount, d.campaign, d.timestamp);
    }

    function getDonations(
        uint256 startIndex,
        uint256 pageSize
    ) external view returns (Donation[] memory) {
        require(startIndex < donationCount, "Start index out of range");
        pageSize = Math.min(pageSize, donationCount - startIndex);
        Donation[] memory result = new Donation[](pageSize);
        for (uint256 i = 0; i < pageSize; i++) {
            result[i] = donations[startIndex + i];
        }
        return result;
    }

    function getDonationCount() external view returns (uint256) {
        return donationCount;
    }

    function getTotalDonatedBy(address donor) external view returns (uint256) {
        return donorTotal[donor];
    }

    function updateTokenAddress(
        address newToken
    ) external onlyRole(OWNER_ROLE) {
        require(newToken != address(0), "Invalid token address");
        token = IERC20(newToken);
    }

    function withdrawToken(
        address _tokenAddress,
        address _to,
        uint256 _amount
    ) external onlyRole(OWNER_ROLE) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_to != address(0), "Invalid receiver address");
        require(_amount > 0, "Amount must be greater than zero");

        bool success = IERC20(_tokenAddress).transfer(_to, _amount);
        require(success, "Token withdrawal failed");

        emit TokenWithdrawn(_tokenAddress, _to, _amount);
    }
}
