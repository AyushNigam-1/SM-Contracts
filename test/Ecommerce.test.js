const { expect } = require("chai");
const hre = require("hardhat");

describe("SecureEcommerce - Intense Testing", function () {
    let SecureEcommerce, ecommerce, token, owner, vendor, buyer, refundManager;

    before(async function () {
        const signers = await hre.ethers.getSigners();
        [owner, vendor, buyer, refundManager] = signers;

        // Deploy mock ERC20 token
        const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
        token = await MockERC20.deploy("MockERC20", "MTK", hre.ethers.parseEther("10000"));

        // Deploy SecureEcommerce contract
        SecureEcommerce = await hre.ethers.getContractFactory("SecureEcommerce");
        ecommerce = await SecureEcommerce.deploy(token.address);

        // Grant roles
        await ecommerce.connect(owner).grantRole(await ecommerce.VENDOR_ROLE(), vendor.address);
        await ecommerce.connect(owner).grantRole(await ecommerce.ORDER_MANAGER_ROLE(), owner.address);
        await ecommerce.connect(owner).grantRole(await ecommerce.REFUND_MANAGER_ROLE(), refundManager.address);
    });

    it("Should prevent unauthorized users from adding products", async function () {
        await expect(
            ecommerce.connect(buyer).addProduct(
                "UnauthorizedProduct",
                "NotAllowed",
                hre.ethers.utils.parseEther("10"),
                10
            )
        ).to.be.revertedWith("Not a vendor");
    });

    it("Should allow vendor to add products", async function () {
        await ecommerce.connect(vendor).addProduct(
            "ValidProduct",
            "Description",
            hre.ethers.utils.parseEther("10"),
            100
        );

        const product = await ecommerce.products(1);
        expect(product.name).to.equal("ValidProduct");
        expect(product.vendor).to.equal(vendor.address);
    });

    it("Should allow buyer to place an order", async function () {
        await token.connect(buyer).approve(ecommerce.address, hre.ethers.utils.parseEther("20"));

        await ecommerce.connect(buyer).placeOrder([1], [2]);

        const order = await ecommerce.orders(1);
        expect(order.buyer).to.equal(buyer.address);
        expect(order.totalAmount).to.equal(hre.ethers.utils.parseEther("20"));
    });

    it("Should handle refunds properly", async function () {
        await ecommerce.connect(refundManager).refundOrder(1);

        const order = await ecommerce.orders(1);
        expect(order.status).to.equal(5); // OrderStatus.Refunded

        const buyerBalance = await token.balanceOf(buyer.address);
        expect(buyerBalance).to.be.gt(hre.ethers.utils.parseEther("9999"));
    });

    it("Should handle large orders correctly", async function () {
        await ecommerce.connect(vendor).addProduct(
            "BulkProduct",
            "Bulk",
            hre.ethers.utils.parseEther("1"),
            5000
        );

        await token.connect(buyer).approve(ecommerce.address, hre.ethers.utils.parseEther("5000"));

        await ecommerce.connect(buyer).placeOrder([2], [5000]);

        const order = await ecommerce.orders(2);
        expect(order.totalAmount).to.equal(hre.ethers.utils.parseEther("5000"));
    });

    it("Should prevent unauthorized role actions", async function () {
        await expect(ecommerce.connect(buyer).updateOrderStatus(1, 3)).to.be.revertedWith(
            "AccessControl: account is missing role"
        );
    });

    it("Should release funds to vendor after order completion", async function () {
        await ecommerce.connect(owner).updateOrderStatus(2, 4); // OrderStatus.Completed
        await ecommerce.connect(owner).releaseFunds(2);

        const balanceBefore = await token.balanceOf(vendor.address);
        await ecommerce.connect(vendor).withdrawPayout();
        const balanceAfter = await token.balanceOf(vendor.address);

        expect(balanceAfter.sub(balanceBefore)).to.equal(hre.ethers.utils.parseEther("5000"));
    });
});
