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

contract CharityDonationProof is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    IKnowledgeToken public immutable token;

    struct Donation {
        address donor;
        address receiver;
        uint256 amount;
        string campaignId;
        uint256 timestamp;
        string proofHash;
    }

    uint256 public donationCount;

    mapping(string => address) public campaignReceivers; // campaignId => receiver address
    mapping(uint256 => Donation) public donations;

    event CampaignAdded(string campaignId, address receiver);
    event CampaignRemoved(string campaignId);
    event DonationReceived(
        address indexed donor,
        uint256 amount,
        string campaignId,
        uint256 donationId
    );
    event ProofSubmitted(uint256 indexed donationId, string proofHash);

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");

        token = IKnowledgeToken(_tokenAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
    }

    modifier validCampaign(string memory campaignId) {
        require(
            campaignReceivers[campaignId] != address(0),
            "Campaign does not exist"
        );
        _;
    }

    function addCampaign(
        string calldata campaignId,
        address receiver
    ) external onlyRole(OWNER_ROLE) {
        require(bytes(campaignId).length > 0, "Campaign ID required");
        require(receiver != address(0), "Invalid receiver address");
        require(
            campaignReceivers[campaignId] == address(0),
            "Campaign already exists"
        );

        campaignReceivers[campaignId] = receiver;

        emit CampaignAdded(campaignId, receiver);
    }

    function removeCampaign(
        string calldata campaignId
    ) external onlyRole(OWNER_ROLE) {
        require(
            campaignReceivers[campaignId] != address(0),
            "Campaign does not exist"
        );

        delete campaignReceivers[campaignId];

        emit CampaignRemoved(campaignId);
    }

    function donate(
        string calldata campaignId,
        uint256 amount
    ) external nonReentrant whenNotPaused validCampaign(campaignId) {
        require(amount > 0, "Amount must be greater than zero");

        address receiver = campaignReceivers[campaignId];

        bool success = token.transferFrom(msg.sender, receiver, amount);
        require(success, "Token transfer failed");

        donations[donationCount] = Donation({
            donor: msg.sender,
            receiver: receiver,
            amount: amount,
            campaignId: campaignId,
            timestamp: block.timestamp,
            proofHash: ""
        });

        emit DonationReceived(msg.sender, amount, campaignId, donationCount);

        donationCount++;
    }

    function submitProof(
        uint256 donationId,
        string calldata proofHash
    ) external onlyRole(OWNER_ROLE) whenNotPaused {
        require(donationId < donationCount, "Invalid donation ID");
        require(bytes(proofHash).length > 0, "Proof hash required");
        require(
            bytes(donations[donationId].proofHash).length == 0,
            "Proof already submitted"
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
