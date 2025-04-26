const { expect } = require("chai");
const hre = require("hardhat");

describe("CharityDonationProof", function () {
    let contract, token, owner, user, receiver;
    const parseEther = hre.ethers.parseEther;

    beforeEach(async function () {
        [owner, user, receiver] = await hre.ethers.getSigners();

        const MockToken = await hre.ethers.getContractFactory("MockERC20");
        token = await MockToken.deploy("Knowledge Token", "KNW", parseEther("1000000"));
        await token.waitForDeployment();

        const CharityDonationProof = await hre.ethers.getContractFactory("CharityDonationProof");
        contract = await CharityDonationProof.deploy(await token.getAddress());
        await contract.waitForDeployment();

        const OWNER_ROLE = await contract.OWNER_ROLE();
        await contract.grantRole(OWNER_ROLE, owner.address);
    });

    it("should add and remove campaigns", async function () {
        await contract.addCampaign("food_march", receiver.address);
        expect(await contract.campaignReceivers("food_march")).to.equal(receiver.address);

        await contract.removeCampaign("food_march");
        expect(await contract.campaignReceivers("food_march")).to.equal(hre.ethers.ZeroAddress);
    });

    it("should allow user to donate to valid campaign", async function () {
        await contract.addCampaign("education_drive", receiver.address);

        await token.transfer(user.address, parseEther("100"));
        await token.connect(user).approve(await contract.getAddress(), parseEther("100"));

        await contract.connect(user).donate("education_drive", parseEther("50"));

        const donation = await contract.getDonation(0);
        expect(donation.donor).to.equal(user.address);
        expect(donation.receiver).to.equal(receiver.address);
        expect(donation.amount).to.equal(parseEther("50"));
    });

    it("should submit proof for a donation", async function () {
        await contract.addCampaign("temple_help", receiver.address);

        await token.transfer(user.address, parseEther("100"));
        await token.connect(user).approve(await contract.getAddress(), parseEther("100"));
        await contract.connect(user).donate("temple_help", parseEther("10"));

        await contract.submitProof(0, "QmProofHashExample");

        const donation = await contract.getDonation(0);
        expect(donation.proofHash).to.equal("QmProofHashExample");
    });

    it("should reject donation to invalid campaign", async function () {
        await expect(contract.connect(user).donate("invalid_campaign", parseEther("10")))
            .to.be.revertedWith("Campaign does not exist");
    });
});
