const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RewardContract", function () {
    let RewardContract, MockToken;
    let rewardContract, token;
    let admin, manager, user, nonManager;

    const parseEther = ethers.parseEther;

    beforeEach(async () => {
        [admin, manager, user, nonManager] = await ethers.getSigners();

        MockToken = await ethers.getContractFactory("MockXRC20");
        token = await MockToken.deploy("KnowledgeToken", "KNW", parseEther("1000000"));
        await token.waitForDeployment();

        RewardContract = await ethers.getContractFactory("RewardContract");
        rewardContract = await RewardContract.deploy(token.target);
        await rewardContract.waitForDeployment();

        await rewardContract.grantRole(await rewardContract.REWARD_MANAGER_ROLE(), manager.address);
        await token.transfer(rewardContract.target, parseEther("1000"));
    });

    it("should allow manager to issue reward", async () => {
        await rewardContract.connect(manager).issueReward(user.address, parseEther("50"));
        const balance = await token.balanceOf(user.address);
        expect(balance).to.equal(parseEther("50"));
    });

    it("should revert if non-manager tries to issue reward", async () => {
        await expect(
            rewardContract.connect(nonManager).issueReward(user.address, parseEther("10"))
        ).to.be.revertedWithCustomError(
            rewardContract,
            "AccessControlUnauthorizedAccount"
        ).withArgs(nonManager.address, await rewardContract.REWARD_MANAGER_ROLE());
    });

    it("should withdraw tokens by admin", async () => {
        const amount = parseEther("100");

        const contractBalanceBefore = await token.balanceOf(rewardContract.target);
        const adminBalanceBefore = await token.balanceOf(admin.address);

        await rewardContract.withdrawTokens(admin.address, amount);

        const contractBalanceAfter = await token.balanceOf(rewardContract.target);
        const adminBalanceAfter = await token.balanceOf(admin.address);

        expect(contractBalanceAfter).to.equal(contractBalanceBefore - amount);
        expect(adminBalanceAfter).to.equal(adminBalanceBefore + amount);
    });

    it("should revert reward if contract paused", async () => {
        await rewardContract.pause();

        await expect(
            rewardContract.connect(manager).issueReward(user.address, parseEther("10"))
        ).to.be.revertedWithCustomError(rewardContract, "EnforcedPause");

        await rewardContract.unpause();

        await rewardContract.connect(manager).issueReward(user.address, parseEther("10"));
        const balance = await token.balanceOf(user.address);
        expect(balance).to.equal(parseEther("10"));
    });
});
