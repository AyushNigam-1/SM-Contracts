// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

interface IKnowledgeToken {
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

contract EDonation is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    IKnowledgeToken public immutable token;

    struct Campaign {
        address creator;
        address receiver;
        bool active;
    }

    struct Donation {
        uint256 donationId;
        address donor;
        uint256 amount;
        string campaignId;
        uint256 timestamp;
        string proofHash;
    }

    mapping(string => Campaign) public campaigns;
    mapping(uint256 => Donation) public donations;
    mapping(string => uint256[]) public campaignDonationIds;
    mapping(string => uint256) public campaignTotalDonations;

    uint256 public donationCount;

    event CampaignCreated(string campaignId, address creator, address receiver);
    event CampaignApproved(string campaignId);
    event DonationReceived(
        address indexed donor,
        uint256 amount,
        string campaignId,
        uint256 donationId
    );
    event ProofSubmitted(uint256 indexed donationId, string proofHash);

    constructor(address tokenAddress) {
        require(tokenAddress != address(0), "Invalid token address");
        token = IKnowledgeToken(tokenAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    modifier campaignExists(string memory campaignId) {
        require(
            campaigns[campaignId].receiver != address(0),
            "Campaign does not exist"
        );
        _;
    }

    modifier campaignIsActive(string memory campaignId) {
        require(campaigns[campaignId].active, "Campaign not active");
        _;
    }

    function createCampaign(
        string calldata campaignId,
        address receiver
    ) external whenNotPaused {
        require(bytes(campaignId).length > 0, "Campaign ID required");
        require(receiver != address(0), "Invalid receiver address");
        require(
            campaigns[campaignId].receiver == address(0),
            "Campaign already exists"
        );

        campaigns[campaignId] = Campaign({
            creator: msg.sender,
            receiver: receiver,
            active: false
        });

        emit CampaignCreated(campaignId, msg.sender, receiver);
    }

    function approveCampaign(
        string calldata campaignId
    ) external onlyRole(OWNER_ROLE) whenNotPaused {
        require(
            campaigns[campaignId].receiver != address(0),
            "Campaign does not exist"
        );
        require(!campaigns[campaignId].active, "Already active");

        campaigns[campaignId].active = true;
        emit CampaignApproved(campaignId);
    }

    function donate(
        string calldata campaignId,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        campaignExists(campaignId)
        campaignIsActive(campaignId)
    {
        require(amount > 0, "Amount must be greater than zero");

        bool success = token.transferFrom(
            msg.sender,
            campaigns[campaignId].receiver,
            amount
        );
        require(success, "Token transfer failed");

        donations[donationCount] = Donation({
            donationId: donationCount,
            donor: msg.sender,
            amount: amount,
            campaignId: campaignId,
            timestamp: block.timestamp,
            proofHash: ""
        });

        campaignTotalDonations[campaignId] += amount;
        campaignDonationIds[campaignId].push(donationCount);

        emit DonationReceived(msg.sender, amount, campaignId, donationCount);
        donationCount++;
    }

    function submitProof(
        uint256 donationId,
        string calldata proofHash
    ) external whenNotPaused {
        require(donationId < donationCount, "Invalid donation ID");
        require(bytes(proofHash).length > 0, "Proof hash required");
        require(
            bytes(donations[donationId].proofHash).length == 0,
            "Proof already submitted"
        );

        // Only the campaign receiver can submit proof
        string memory campaignId = donations[donationId].campaignId;
        require(
            campaigns[campaignId].receiver == msg.sender,
            "Not authorized to submit proof"
        );

        donations[donationId].proofHash = proofHash;
        emit ProofSubmitted(donationId, proofHash);
    }

    function getDonation(
        uint256 donationId
    ) external view returns (Donation memory) {
        require(donationId < donationCount, "Invalid donation ID");
        return donations[donationId];
    }

    function getDonationsForCampaign(
        string calldata campaignId
    ) external view returns (uint256[] memory) {
        return campaignDonationIds[campaignId];
    }

    function getTotalDonationsForCampaign(
        string calldata campaignId
    ) external view returns (uint256) {
        return campaignTotalDonations[campaignId];
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
