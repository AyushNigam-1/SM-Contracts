const { expect } = require("chai");
const hre = require("hardhat");
const parse = hre.ethers.parseEther;

describe("MealDonationContract", function () {
    let contract, token, owner, donor, treasury;

    beforeEach(async () => {
        [owner, donor, treasury] = await hre.ethers.getSigners();

        const MockToken = await hre.ethers.getContractFactory("MockERC20");
        token = await MockToken.deploy("RW-TMCG", "RW", parse("1000000"));
        await token.waitForDeployment();

        const MealDonation = await hre.ethers.getContractFactory("MealDonationContract");
        contract = await MealDonation.deploy(await token.getAddress(), treasury.address);
        await contract.waitForDeployment();

        await contract.grantRole(await contract.OWNER_ROLE(), owner.address);
    });

    it("should allow a donor to donate tokens for meals", async () => {
        const amount = parse("100");
        await token.transfer(donor.address, amount);
        await token.connect(donor).approve(contract.target, amount);

        await expect(contract.connect(donor).donateMeals(amount)).to.emit(contract, "MealDonated");

        const donation = await contract.getDonation(0);
        expect(donation.amount).to.equal(amount);
        expect(donation.donor).to.equal(donor.address);
        expect(donation.meals).to.equal(10); // tokensPerMeal = 10e18

        const totalMeals = await contract.getTotalMealsBy(donor.address);
        expect(totalMeals).to.equal(10);
    });

    it("should reject donation if amount is zero", async () => {
        await expect(contract.connect(donor).donateMeals(0)).to.be.revertedWith("Amount must be > 0");
    });

    it("should allow owner to update donation rate", async () => {
        await expect(contract.connect(owner).setTokensPerMeal(parse("20")))
            .to.emit(contract, "TokensPerMealUpdated")
            .withArgs(parse("20"));
    });

    it("should reject rate update by non-owner", async () => {
        await expect(contract.connect(donor).setTokensPerMeal(parse("20"))).to.be.reverted;
    });

    it("should allow owner to update receiver", async () => {
        await expect(contract.connect(owner).setDonationReceiver(donor.address))
            .to.emit(contract, "DonationReceiverUpdated")
            .withArgs(donor.address);
    });

    it("should revert if invalid donation index is accessed", async () => {
        await expect(contract.getDonation(999)).to.be.revertedWith("Invalid index");
    });
});
