const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("EDonation Contract", function () {
    let EDonation, MockToken;
    let donationContract, token;
    let owner, user, receiver;

    const parseEther = ethers.parseEther;

    beforeEach(async () => {
        [owner, user, receiver] = await ethers.getSigners();

        MockToken = await ethers.getContractFactory("MockERC20");
        token = await MockToken.deploy("KnowledgeToken", "KNW", parseEther("1000000"));
        await token.waitForDeployment();

        EDonation = await ethers.getContractFactory("EDonation");
        donationContract = await EDonation.deploy(token.target);
        await donationContract.waitForDeployment();

        const OWNER_ROLE = await donationContract.OWNER_ROLE();
        await donationContract.grantRole(OWNER_ROLE, owner.address);
    });

    it("should create and approve campaign", async () => {
        await donationContract.createCampaign("food_drive", receiver.address);
        await donationContract.approveCampaign("food_drive");

        const campaign = await donationContract.campaigns("food_drive");
        expect(campaign.active).to.equal(true);
    });

    it("should donate successfully", async () => {
        await donationContract.createCampaign("temple", receiver.address);
        await donationContract.approveCampaign("temple");

        await token.transfer(user.address, parseEther("100"));
        await token.connect(user).approve(donationContract.target, parseEther("100"));

        await donationContract.connect(user).donate("temple", parseEther("50"));

        const donation = await donationContract.getDonation(0);
        expect(donation.donor).to.equal(user.address);
        expect(donation.amount).to.equal(parseEther("50"));
        expect(donation.campaignId).to.equal("temple");
    });

    it("should reject donation if paused", async () => {
        await donationContract.createCampaign("edu", receiver.address);
        await donationContract.approveCampaign("edu");

        await token.transfer(user.address, parseEther("10"));
        await token.connect(user).approve(donationContract.target, parseEther("10"));

        await donationContract.pause();

        await expect(
            donationContract.connect(user).donate("edu", parseEther("5"))
        ).to.be.revertedWithCustomError(donationContract, "EnforcedPause");
    });

    it("should allow receiver to submit proof", async () => {
        await donationContract.createCampaign("books", receiver.address);
        await donationContract.approveCampaign("books");

        await token.transfer(user.address, parseEther("5"));
        await token.connect(user).approve(donationContract.target, parseEther("5"));

        await donationContract.connect(user).donate("books", parseEther("5"));

        await donationContract.connect(receiver).submitProof(0, "ipfs://proof-hash");

        const updated = await donationContract.getDonation(0);
        expect(updated.proofHash).to.equal("ipfs://proof-hash");
    });

    it("should get all donation IDs for a campaign", async () => {
        await donationContract.createCampaign("ganga", receiver.address);
        await donationContract.approveCampaign("ganga");

        await token.transfer(user.address, parseEther("20"));
        await token.connect(user).approve(donationContract.target, parseEther("20"));

        await donationContract.connect(user).donate("ganga", parseEther("10"));
        await donationContract.connect(user).donate("ganga", parseEther("5"));

        const ids = await donationContract.getDonationsForCampaign("ganga");
        expect(ids.length).to.equal(2);
    });

    it("should get total donation amount for a campaign", async () => {
        await donationContract.createCampaign("relief", receiver.address);
        await donationContract.approveCampaign("relief");

        await token.transfer(user.address, parseEther("30"));
        await token.connect(user).approve(donationContract.target, parseEther("30"));

        await donationContract.connect(user).donate("relief", parseEther("10"));
        await donationContract.connect(user).donate("relief", parseEther("5"));

        const total = await donationContract.getTotalDonationsForCampaign("relief");
        expect(total).to.equal(parseEther("15"));
    });
});
