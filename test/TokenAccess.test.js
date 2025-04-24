const { expect } = require("chai");
const hre = require("hardhat");

describe("TokenAccess Contract", function () {
    let token, accessContract;
    let owner, user, anotherUser;
    const parseEther = hre.ethers.parseEther;

    beforeEach(async () => {
        [owner, user, anotherUser] = await hre.ethers.getSigners();

        const MockToken = await hre.ethers.getContractFactory("MockERC20");
        token = await MockToken.deploy("RW-TMCG", "RW", parseEther("1000000"));
        await token.waitForDeployment();

        const TokenAccess = await hre.ethers.getContractFactory("TokenAccess");
        accessContract = await TokenAccess.deploy(await token.getAddress(), parseEther("10"));
        await accessContract.waitForDeployment();

        const ADMIN_ROLE = await accessContract.ADMIN_ROLE();
        await accessContract.grantRole(ADMIN_ROLE, owner.address);
    });

    it("should allow user to unlock a book", async () => {
        const amount = parseEther("10");
        await token.transfer(user.address, amount);
        await token.connect(user).approve(await accessContract.getAddress(), amount);

        await expect(accessContract.connect(user).unlock("BhagavadGita"))
            .to.emit(accessContract, "AccessGranted");

        expect(await accessContract.checkAccess(user.address, "BhagavadGita")).to.be.true;
    });

    it("should reject duplicate unlock", async () => {
        const amount = parseEther("10");
        await token.transfer(user.address, amount * 2n);
        await token.connect(user).approve(await accessContract.getAddress(), amount * 2n);
        await accessContract.connect(user).unlock("BhagavadGita");

        await expect(
            accessContract.connect(user).unlock("BhagavadGita")
        ).to.be.revertedWith("Already unlocked");
    });

    it("should allow admin to update access fee", async () => {
        await accessContract.setAccessFee(parseEther("20"));
        expect(await accessContract.accessFee()).to.equal(parseEther("20"));
    });

    it("should allow admin to withdraw tokens", async () => {
        const amount = parseEther("10");
        await token.transfer(user.address, amount);
        await token.connect(user).approve(await accessContract.getAddress(), amount);
        await accessContract.connect(user).unlock("Vedas");

        await expect(
            accessContract.withdrawTokens(owner.address, amount)
        ).to.emit(accessContract, "TokenWithdrawn");
    });

    it("should store access log", async () => {
        const amount = parseEther("10");
        await token.transfer(user.address, amount);
        await token.connect(user).approve(await accessContract.getAddress(), amount);
        await accessContract.connect(user).unlock("Upanishads");

        const [userAddr, book, _] = await accessContract.getAccessLog(0);
        expect(userAddr).to.equal(user.address);
        expect(book).to.equal("Upanishads");
    });
});
