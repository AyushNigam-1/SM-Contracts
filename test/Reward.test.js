const { expect } = require("chai");
const hre = require("hardhat");

describe("RewardContract", function () {
    let rewardToken, rewardContract;
    let admin, manager, user;

    beforeEach(async () => {
        [admin, manager, user] = await hre.ethers.getSigners();

        const MockToken = await hre.ethers.getContractFactory("MockERC20");
        rewardToken = await MockToken.deploy("RewardToken", "RWT", hre.ethers.parseEther("1000000"));
        await rewardToken.waitForDeployment();

        const RewardContract = await hre.ethers.getContractFactory("RewardContract");
        rewardContract = await RewardContract.deploy(await rewardToken.getAddress(), 5); // 5% rate
        await rewardContract.waitForDeployment();

        // Give contract some reward tokens
        await rewardToken.transfer(await rewardContract.getAddress(), hre.ethers.parseEther("100000"));

        // Grant REWARD_MANAGER_ROLE to manager
        const ROLE = await rewardContract.REWARD_MANAGER_ROLE();
        await rewardContract.connect(admin).grantRole(ROLE, manager.address);
    });

    it("should issue rewards based on rate", async () => {
        const baseAmount = hre.ethers.parseEther("1000");
        await rewardContract.connect(manager).issueReward(user.address, baseAmount);

        const userBalance = await rewardToken.balanceOf(user.address);
        expect(userBalance).to.equal(hre.ethers.parseEther("50")); // 5% of 1000

        const totalGiven = await rewardContract.rewardsGiven(user.address);
        expect(totalGiven).to.equal(hre.ethers.parseEther("50"));
    });

    it("should not issue reward from non-manager", async () => {
        const baseAmount = hre.ethers.parseEther("1000");
        await expect(
            rewardContract.connect(user).issueReward(user.address, baseAmount)
        ).to.be.revertedWithCustomError(rewardContract, "AccessControlUnauthorizedAccount");

    });

    it("should update reward rate by admin", async () => {
        await rewardContract.connect(admin).setRewardRate(10);
        expect(await rewardContract.rewardRate()).to.equal(10);
    });

    it("should prevent reward rate update by non-admin", async () => {
        await expect(
            rewardContract.connect(user).setRewardRate(15)
        ).to.be.revertedWithCustomError(rewardContract, "AccessControlUnauthorizedAccount");

    });

    it("should revert if contract balance is insufficient", async () => {
        const baseAmount = hre.ethers.parseEther("5000000"); // way more than balance
        await expect(
            rewardContract.connect(manager).issueReward(user.address, baseAmount)
        ).to.be.revertedWith("Insufficient contract balance");
    });
});
