const { expect } = require("chai");
const hre = require("hardhat");

const parseEther = hre.ethers.parseEther;

describe("SecureEcommerce", function () {
    let ecommerce, token, owner, vendor, buyer, refundManager, orderManager;

    beforeEach(async () => {
        [owner, vendor, buyer, refundManager, orderManager] = await hre.ethers.getSigners();

        const MockToken = await hre.ethers.getContractFactory("MockERC20");
        token = await MockToken.deploy("TestToken", "TTK", parseEther("1000000"));
        await token.waitForDeployment();

        const SecureEcommerce = await hre.ethers.getContractFactory("SecureEcommerce");
        ecommerce = await SecureEcommerce.deploy(await token.getAddress());
        await ecommerce.waitForDeployment();

        await ecommerce.grantRole(await ecommerce.VENDOR_ROLE(), vendor.address);
        await ecommerce.grantRole(await ecommerce.ORDER_MANAGER_ROLE(), orderManager.address);
        await ecommerce.grantRole(await ecommerce.REFUND_MANAGER_ROLE(), refundManager.address);
    });

    it("should allow vendor to add, update, and remove a product", async () => {
        await ecommerce.connect(vendor).addProduct("Book", "Spiritual book", 100, 5);
        let product = await ecommerce.products(1);
        expect(product.name).to.equal("Book");

        await ecommerce.connect(vendor).updateProduct(1, "Holy Book", 150, 10);
        product = await ecommerce.products(1);
        expect(product.price).to.equal(150);

        await ecommerce.connect(vendor).removeProduct(1);
        product = await ecommerce.products(1);
        expect(product.exists).to.equal(false);
    });

    it("should place order and hold funds in escrow", async () => {
        await ecommerce.connect(vendor).addProduct("Puja Kit", "Essentials", 50, 10);
        await token.transfer(buyer.address, parseEther("100"));
        await token.connect(buyer).approve(await ecommerce.getAddress(), parseEther("100"));

        await ecommerce.connect(buyer).placeOrder([1], [2]);
        const order = await ecommerce.orders(1);
        expect(order.totalAmount).to.equal(100);
    });

    it("should release funds to vendor after order is completed", async () => {
        await ecommerce.connect(vendor).addProduct("Bell", "Temple bell", 40, 10);
        await token.transfer(buyer.address, parseEther("80"));
        await token.connect(buyer).approve(await ecommerce.getAddress(), parseEther("80"));
        await ecommerce.connect(buyer).placeOrder([1], [2]);

        await ecommerce.connect(orderManager).updateOrderStatus(1, 3); // Completed
        await ecommerce.connect(orderManager).releaseFunds(1);

        await ecommerce.connect(vendor).withdrawPayout();
        const balance = await token.balanceOf(vendor.address);
        expect(balance).to.equal(80);
    });

    it("should refund buyer if dispute or placed", async () => {
        await ecommerce.connect(vendor).addProduct("Ganga Jal", "Sacred", 30, 3);
        await token.transfer(buyer.address, parseEther("30"));
        await token.connect(buyer).approve(await ecommerce.getAddress(), parseEther("30"));
        await ecommerce.connect(buyer).placeOrder([1], [1]);

        await ecommerce.connect(refundManager).refundOrder(1);
        const balance = await token.balanceOf(buyer.address);
        expect(balance).to.equal(parseEther("30"));
        ;
    });

    it("should reject refund if Can't refund", async () => {
        await ecommerce.connect(vendor).addProduct("Lamp", "Clay", 20, 3);
        await token.transfer(buyer.address, parseEther("20"));
        await token.connect(buyer).approve(await ecommerce.getAddress(), parseEther("20"));
        await ecommerce.connect(buyer).placeOrder([1], [1]);
        await ecommerce.connect(orderManager).updateOrderStatus(1, 3);
        await ecommerce.connect(orderManager).releaseFunds(1);

        await expect(ecommerce.connect(refundManager).refundOrder(1)).to.be.revertedWith("Can't refund");
    });

    it("should prevent non-vendors from managing products", async () => {
        await expect(ecommerce.connect(buyer).addProduct("Fake", "Hack", 10, 1)).to.be.revertedWith("Not a vendor");
    });

    it("should reject withdrawal with no balance", async () => {
        await expect(ecommerce.connect(vendor).withdrawPayout()).to.be.revertedWith("No funds");
    });
});
