const { expect } = require("chai");
const hre = require("hardhat");
const { parseEther } = hre.ethers;

describe("KnowledgeToken", function () {
    let token, owner, user, spender, treasury;

    beforeEach(async () => {
        [owner, user, spender, treasury] = await hre.ethers.getSigners();

        const Token = await hre.ethers.getContractFactory("KnowledgeToken");
        token = await Token.deploy(parseEther("1000"), treasury.address);
        await token.waitForDeployment();
    });

    it("should initialize with total supply", async () => {
        const supply = await token.totalSupply();
        const balance = await token.balanceOf(treasury.address);
        expect(supply).to.equal(parseEther("1000"));
        expect(balance).to.equal(parseEther("1000"));
    });

    it("should allow transfer between accounts", async () => {
        await token.connect(treasury).transfer(user.address, parseEther("100"));
        const balance = await token.balanceOf(user.address);
        expect(balance).to.equal(parseEther("100"));
    });

    it("should approve and transferFrom correctly", async () => {
        await token.connect(treasury).approve(spender.address, parseEther("200"));
        await token.connect(spender).transferFrom(treasury.address, user.address, parseEther("150"));

        const balance = await token.balanceOf(user.address);
        const remaining = await token.allowance(treasury.address, spender.address);
        expect(balance).to.equal(parseEther("150"));
        expect(remaining).to.equal(parseEther("50"));
    });

    it("should increase and decrease allowance", async () => {
        await token.connect(treasury).increaseAllowance(spender.address, parseEther("100"));
        let allowance = await token.allowance(treasury.address, spender.address);
        expect(allowance).to.equal(parseEther("100"));

        await token.connect(treasury).decreaseAllowance(spender.address, parseEther("40"));
        allowance = await token.allowance(treasury.address, spender.address);
        expect(allowance).to.equal(parseEther("60"));
    });

    it("should mint tokens only by owner", async () => {
        await token.connect(owner).mint(user.address, parseEther("500"));
        const balance = await token.balanceOf(user.address);
        expect(balance).to.equal(parseEther("500"));
    });

    it("should burn tokens by self", async () => {
        await token.connect(treasury).burn(parseEther("300"));
        const balance = await token.balanceOf(treasury.address);
        expect(balance).to.equal(parseEther("700"));
    });

    it("should burn from approved account", async () => {
        await token.connect(treasury).approve(spender.address, parseEther("200"));
        await token.connect(spender).burnFrom(treasury.address, parseEther("200"));
        const balance = await token.balanceOf(treasury.address);
        expect(balance).to.equal(parseEther("800"));
    });

    it("should transfer ownership", async () => {
        await token.connect(owner).updateOwner(user.address);
        const newOwner = await token.owner();
        expect(newOwner).to.equal(user.address);
    });
});
