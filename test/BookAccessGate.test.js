const { expect } = require("chai");
const hre = require("hardhat");

describe("BookTokenAccess", function () {
    let access, token, owner, manager, user;
    const parseEther = hre.ethers.parseEther;

    beforeEach(async () => {
        [owner, manager, user] = await hre.ethers.getSigners();

        const Token = await hre.ethers.getContractFactory("MockERC20");
        token = await Token.deploy("Test", "TST", parseEther("1000000"));
        await token.waitForDeployment();

        const BookAccess = await hre.ethers.getContractFactory("BookTokenAccess");
        access = await BookAccess.deploy(await token.getAddress());
        await access.waitForDeployment();

        await access.grantRole(await access.BOOK_MANAGER_ROLE(), manager.address);
        await token.transfer(user.address, parseEther("100"));
    });

    it("should allow manager to add, update and delete a book", async () => {
        await access.connect(manager).addBook(101, parseEther("5"));
        let book = await access.books(101);
        expect(book.tokenCost).to.equal(parseEther("5"));

        await access.connect(manager).updateBook(101, parseEther("7"));
        book = await access.books(101);
        expect(book.tokenCost).to.equal(parseEther("7"));

        await access.connect(manager).deleteBook(101);
        book = await access.books(101);
        expect(book.exists).to.equal(false);
    });

    it("should allow user to unlock access by paying tokens", async () => {
        await access.connect(manager).addBook(42, parseEther("5"));
        await token.connect(user).approve(await access.getAddress(), parseEther("5"));

        await expect(access.connect(user).unlockBook(42))
            .to.emit(access, "AccessGranted")
            .withArgs(user.address, 42);

        expect(await access.hasAccess(user.address, 42)).to.equal(true);
    });

    it("should prevent duplicate unlock", async () => {
        await access.connect(manager).addBook(77, parseEther("3"));
        await token.connect(user).approve(await access.getAddress(), parseEther("10"));
        await access.connect(user).unlockBook(77);

        await expect(access.connect(user).unlockBook(77)).to.be.revertedWith("Already unlocked");
    });

    it("should withdraw tokens to admin", async () => {
        await access.connect(manager).addBook(55, parseEther("5"));
        await token.connect(user).approve(await access.getAddress(), parseEther("5"));
        await access.connect(user).unlockBook(55);

        const before = await token.balanceOf(owner.address);
        await access.withdrawTokens(owner.address, parseEther("5"));
        const after = await token.balanceOf(owner.address);

        expect(after - before).to.equal(parseEther("5"));
    });
});
