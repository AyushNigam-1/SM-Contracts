// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract EDonations is ReentrancyGuard, AccessControl {
    using Strings for uint256;

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    IERC20 public token; // RW-TMCG or other ERC20 token

    struct Donation {
        address donor;
        address receiver;
        uint256 amount;
        string campaign;
        uint256 timestamp;
    }

    // Using a mapping with a counter for pagination
    mapping(uint256 => Donation) public donations;
    uint256 public donationCount;
    mapping(address => uint256) public donorTotal;

    mapping(string => bool) public validCampaigns;
    mapping(string => address) public campaignReceivers;

    uint256 public constant MAX_CAMPAIGN_NAME_LENGTH = 64; // Arbitrary limit

    event DonationReceived(
        address indexed donor,
        address indexed receiver,
        uint256 amount,
        string campaign,
        uint256 timestamp
    );

    constructor(address _tokenAddress) {
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Optionally grant admin role too
        token = IERC20(_tokenAddress);
    }

    modifier onlyCampaign(string memory campaign) {
        require(validCampaigns[campaign], "Invalid campaign");
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
        require(receiver != address(0), "Invalid receiver");
        validCampaigns[name] = true;
        campaignReceivers[name] = receiver;
    }

    function removeCampaign(string memory name) external onlyRole(OWNER_ROLE) {
        delete validCampaigns[name];
        delete campaignReceivers[name];
    }

    function isCampaignValid(string memory name) external view returns (bool) {
        return validCampaigns[name];
    }

    function donate(
        string calldata campaign,
        uint256 amount
    ) external payable onlyCampaign(campaign) nonReentrant {
        require(amount > 0, "Amount must be > 0");

        address receiver = campaignReceivers[campaign];
        require(receiver != address(0), "No receiver set for campaign");

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
        require(index < donationCount, "Invalid index");
        Donation memory d = donations[index];
        return (d.donor, d.receiver, d.amount, d.campaign, d.timestamp);
    }

    // Pagination - return a limited number of donations
    function getDonations(
        uint256 startIndex,
        uint256 pageSize
    ) external view returns (Donation[] memory) {
        require(startIndex < donationCount, "Start index out of bounds");
        pageSize = Math.min(pageSize, donationCount - startIndex); // Prevent out-of-bounds reads
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
        require(newToken != address(0), "Invalid token");
        token = IERC20(newToken);
    }

    // Owner can withdraw any stuck tokens
    function withdrawToken(
        address _tokenAddress,
        address _to,
        uint256 _amount
    ) external onlyRole(OWNER_ROLE) {
        IERC20(_tokenAddress).transfer(_to, _amount);
    }
}
