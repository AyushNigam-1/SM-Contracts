const { expect } = require("chai");
const hre = require("hardhat");

describe("EDonations Contract", function () {
    let owner, user, treasury, token, donationContract;
    const parseEther = hre.ethers.parseEther;

    beforeEach(async () => {
        [owner, user, treasury, otherReceiver] = await hre.ethers.getSigners();

        // Deploy mock token
        const MockToken = await hre.ethers.getContractFactory("MockERC20");
        token = await MockToken.deploy("RW-TMCG", "RW", parseEther("1000000"));
        await token.waitForDeployment();

        // Deploy donation contract
        const EDonations = await hre.ethers.getContractFactory("EDonations");
        donationContract = await EDonations.deploy(await token.getAddress());
        await donationContract.waitForDeployment();

        // Grant owner role
        const OWNER_ROLE = await donationContract.OWNER_ROLE();
        await donationContract.grantRole(OWNER_ROLE, owner.address);
    });

    it("should allow owner to add a new campaign", async () => {
        await expect(donationContract.addCampaign("meal_march", treasury.address))
            .to.emit(donationContract, "CampaignAdded")
            .withArgs("meal_march", treasury.address);

        expect(await donationContract.isCampaignValid("meal_march")).to.equal(true);
    });

    it("should prevent duplicate campaign addition", async () => {
        await donationContract.addCampaign("meal_march", treasury.address);
        await expect(
            donationContract.addCampaign("meal_march", treasury.address)
        ).to.be.revertedWith("Campaign already exists");
    });

    it("should allow user to donate to a valid campaign", async () => {
        await donationContract.addCampaign("temple_mumbai", treasury.address);

        const amount = parseEther("100");
        await token.transfer(user.address, amount);
        await token.connect(user).approve(await donationContract.getAddress(), amount);

        await expect(donationContract.connect(user).donate("temple_mumbai", amount))
            .to.emit(donationContract, "DonationReceived");

        expect(await token.balanceOf(treasury.address)).to.equal(amount);
    });

    it("should reject donation to an invalid campaign", async () => {
        const amount = parseEther("10");
        await token.transfer(user.address, amount);
        await token.connect(user).approve(await donationContract.getAddress(), amount);

        await expect(
            donationContract.connect(user).donate("invalid", amount)
        ).to.be.revertedWith("Campaign not active");
    });

    it("should store and return donation data", async () => {
        await donationContract.addCampaign("temple_mumbai", treasury.address);
        const amount = parseEther("10");
        await token.transfer(user.address, amount);
        await token.connect(user).approve(await donationContract.getAddress(), amount);
        await donationContract.connect(user).donate("temple_mumbai", amount);

        const donation = await donationContract.getDonation(0);
        expect(donation.donor).to.equal(user.address);
        expect(donation.receiver).to.equal(treasury.address);
        expect(donation.amount).to.equal(amount);
        expect(donation.campaign).to.equal("temple_mumbai");
    });

    it("should paginate donations", async () => {
        await donationContract.addCampaign("general", treasury.address);
        const amount = parseEther("1");
        await token.transfer(user.address, amount * 3n); // use BigInt
        await token.connect(user).approve(await donationContract.getAddress(), amount * 3n);

        for (let i = 0; i < 3; i++) {
            await donationContract.connect(user).donate("general", amount);
        }

        const donations = await donationContract.getDonations(0, 2);
        expect(donations.length).to.equal(2);
    });

    it("should prevent non-owners from adding campaigns", async () => {
        const OWNER_ROLE = await donationContract.OWNER_ROLE();
        await expect(
            donationContract.connect(user).addCampaign("unauthorized", treasury.address)
        ).to.be.revertedWithCustomError(donationContract, "AccessControlUnauthorizedAccount")
            .withArgs(user.address, OWNER_ROLE);
    });


    it("should allow admin to withdraw stuck tokens", async () => {
        const testAmount = parseEther("50");
        await token.transfer(await donationContract.getAddress(), testAmount);

        await expect(
            donationContract.withdrawToken(await token.getAddress(), treasury.address, testAmount)
        ).to.emit(donationContract, "TokenWithdrawn");

        expect(await token.balanceOf(treasury.address)).to.equal(testAmount);
    });
});
