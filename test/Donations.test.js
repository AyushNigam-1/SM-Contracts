const { expect } = require("chai");
const hre = require("hardhat");

describe("EDonation Updated Contract", function () {
    let donationContract, token, owner, user, receiver, otherUser;
    const parseEther = hre.ethers.parseEther;

    beforeEach(async () => {
        [owner, user, receiver, otherUser] = await hre.ethers.getSigners();

        const Token = await hre.ethers.getContractFactory("MockERC20");
        token = await Token.deploy("KnowledgeToken", "KNW", parseEther("1000000"));
        await token.waitForDeployment();

        const EDonation = await hre.ethers.getContractFactory("EDonation");
        donationContract = await EDonation.deploy(await token.getAddress());
        await donationContract.waitForDeployment();

        await donationContract.grantRole(await donationContract.OWNER_ROLE(), owner.address);
    });

    it("should allow anyone to create a pending campaign", async () => {
        await expect(donationContract.connect(user).createCampaign("temple_food", receiver.address))
            .to.emit(donationContract, "CampaignCreated")
            .withArgs("temple_food", user.address, receiver.address);

        const campaign = await donationContract.campaigns("temple_food");
        expect(campaign.receiver).to.equal(receiver.address);
        expect(campaign.active).to.be.false;
    });

    it("should allow admin to approve a campaign", async () => {
        await donationContract.connect(user).createCampaign("education", receiver.address);
        await expect(donationContract.connect(owner).approveCampaign("education"))
            .to.emit(donationContract, "CampaignApproved");

        const campaign = await donationContract.campaigns("education");
        expect(campaign.active).to.be.true;
    });

    it("should allow donation only to active campaign", async () => {
        await donationContract.connect(user).createCampaign("water_supply", receiver.address);
        await donationContract.connect(owner).approveCampaign("water_supply");

        await token.transfer(user.address, parseEther("100"));
        await token.connect(user).approve(await donationContract.getAddress(), parseEther("100"));

        await expect(donationContract.connect(user).donate("water_supply", parseEther("50")))
            .to.emit(donationContract, "DonationReceived");

        const donation = await donationContract.donations(0);
        expect(donation.amount).to.equal(parseEther("50"));
        expect(donation.campaignId).to.equal("water_supply");
    });

    it("should reject donation to pending campaign", async () => {
        await donationContract.connect(user).createCampaign("health", receiver.address);

        await token.transfer(user.address, parseEther("50"));
        await token.connect(user).approve(await donationContract.getAddress(), parseEther("50"));

        await expect(
            donationContract.connect(user).donate("health", parseEther("50"))
        ).to.be.revertedWith("Campaign not active");
    });

    it("should allow owner to submit proof for donation", async () => {
        await donationContract.connect(user).createCampaign("animal_care", receiver.address);
        await donationContract.connect(owner).approveCampaign("animal_care");

        await token.transfer(user.address, parseEther("20"));
        await token.connect(user).approve(await donationContract.getAddress(), parseEther("20"));
        await donationContract.connect(user).donate("animal_care", parseEther("20"));

        await expect(donationContract.connect(owner).submitProof(0, "QmSomeIPFSHash"))
            .to.emit(donationContract, "ProofSubmitted");

        const donation = await donationContract.donations(0);
        expect(donation.proofHash).to.equal("QmSomeIPFSHash");
    });
});
