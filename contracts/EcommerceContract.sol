// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract SecureEcommerce is ReentrancyGuard, AccessControl {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    // Roles
    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");
    bytes32 public constant ORDER_MANAGER_ROLE =
        keccak256("ORDER_MANAGER_ROLE");
    bytes32 public constant REFUND_MANAGER_ROLE =
        keccak256("REFUND_MANAGER_ROLE");

    IERC20 public token;

    // Products
    struct Product {
        uint256 productId;
        string name;
        string description;
        uint256 price; // Price in token units
        address vendor;
        uint256 stock;
    }

    Counters.Counter private _productIds;
    mapping(uint256 => Product) public products;
    mapping(address => EnumerableSet.UintSet) private _vendorProducts; // Track vendor's products

    // Orders
    enum OrderStatus {
        Placed,
        Shipped,
        Delivered,
        Completed,
        Refunded,
        Cancelled,
        Dispute
    }

    struct Order {
        uint256 orderId;
        address buyer;
        uint256 totalAmount; // Total order amount
        uint256 timestamp;
        OrderStatus status;
    }

    Counters.Counter private _orderIds;
    mapping(uint256 => Order) public orders;
    mapping(address => EnumerableSet.UintSet) private _buyerOrders; // Track buyer's orders

    struct OrderItem {
        uint256 productId;
        uint256 quantity;
        uint256 price; // Price per unit at time of order
    }

    mapping(uint256 => OrderItem[]) public orderItems; // OrderId => Items

    // Events
    event ProductAdded(
        uint256 productId,
        string name,
        address vendor,
        uint256 price,
        uint256 stock
    );
    event ProductUpdated(
        uint256 productId,
        string name,
        uint256 price,
        uint256 stock
    );
    event ProductRemoved(uint256 productId);
    event OrderPlaced(
        uint256 orderId,
        address buyer,
        uint256 totalAmount,
        uint256 timestamp
    );
    event OrderStatusUpdated(uint256 orderId, OrderStatus status);
    event OrderRefunded(uint256 orderId, address buyer, uint256 amount);

    constructor(address _tokenAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        token = IERC20(_tokenAddress);
    }

    // Modifiers
    modifier onlyVendor() {
        require(hasRole(VENDOR_ROLE, msg.sender), "Not a vendor");
        _;
    }

    // Product Management
    function addProduct(
        string memory _name,
        string memory _description,
        uint256 _price,
        uint256 _stock
    ) external onlyVendor {
        require(_price > 0, "Price must be positive");
        require(
            bytes(_name).length > 0 && bytes(_name).length <= 256,
            "Invalid name"
        ); // Example length check

        _productIds.increment();
        uint256 productId = _productIds.current();

        products[productId] = Product({
            productId: productId,
            name: _name,
            description: _description,
            price: _price,
            vendor: msg.sender,
            stock: _stock
        });

        _vendorProducts[msg.sender].add(productId);

        emit ProductAdded(productId, _name, msg.sender, _price, _stock);
    }

    function updateProduct(
        uint256 _productId,
        string memory _name,
        uint256 _price,
        uint256 _stock
    ) external onlyVendor {
        require(
            products[_productId].vendor == msg.sender,
            "Not product vendor"
        );
        require(_price > 0, "Price must be positive");
        require(
            bytes(_name).length > 0 && bytes(_name).length <= 256,
            "Invalid name"
        );

        Product storage product = products[_productId];
        product.name = _name;
        product.price = _price;
        product.stock = _stock;

        emit ProductUpdated(_productId, _name, _price, _stock);
    }

    function removeProduct(uint256 _productId) external onlyVendor {
        require(
            products[_productId].vendor == msg.sender,
            "Not product vendor"
        );
        delete products[_productId];
        _vendorProducts[msg.sender].remove(_productId);
        emit ProductRemoved(_productId);
    }

    function getProduct(
        uint256 _productId
    )
        external
        view
        returns (
            uint256 productId,
            string memory name,
            string memory description,
            uint256 price,
            address vendor,
            uint256 stock
        )
    {
        Product memory product = products[_productId];
        return (
            product.productId,
            product.name,
            product.description,
            product.price,
            product.vendor,
            product.stock
        );
    }

    function getVendorProducts(
        address _vendor
    ) external view returns (uint256[] memory) {
        return _vendorProducts[_vendor].values();
    }

    // Order Placement
    function placeOrder(
        uint256[] memory _productIds,
        uint256[] memory _quantities
    ) external payable nonReentrant returns (uint256 orderId) {
        require(
            _productIds.length > 0 && _productIds.length == _quantities.length,
            "Invalid input"
        );

        _orderIds.increment();
        orderId = _orderIds.current();

        uint256 totalAmount = 0;
        OrderItem[] memory items = new OrderItem[](_productIds.length);

        for (uint256 i = 0; i < _productIds.length; i++) {
            uint256 productId = _productIds[i];
            uint256 quantity = _quantities[i];

            require(
                products[productId].stock >= quantity,
                "Insufficient stock"
            );

            Product storage product = products[productId];
            uint256 itemPrice = product.price * quantity;
            totalAmount += itemPrice;

            product.stock -= quantity; // Optimistic update, revert on failure

            items[i] = OrderItem({
                productId: productId,
                quantity: quantity,
                price: product.price
            });
        }

        // Token transfer
        bool success = token.transferFrom(
            msg.sender,
            address(this),
            totalAmount
        );
        require(success, "Token transfer failed");

        orders[orderId] = Order({
            orderId: orderId,
            buyer: msg.sender,
            totalAmount: totalAmount,
            timestamp: block.timestamp,
            status: OrderStatus.Placed
        });

        orderItems[orderId] = items;
        _buyerOrders[msg.sender].add(orderId);

        emit OrderPlaced(orderId, msg.sender, totalAmount, block.timestamp);

        // Vendor payouts (simplified - can be more complex)
        for (uint256 i = 0; i < _productIds.length; i++) {
            token.transfer(
                products[_productIds[i]].vendor,
                items[i].price * items[i].quantity
            );
        }

        return orderId;
    }

    function getOrder(
        uint256 _orderId
    )
        external
        view
        returns (
            uint256 orderId,
            address buyer,
            uint256 totalAmount,
            uint256 timestamp,
            OrderStatus status
        )
    {
        Order memory order = orders[_orderId];
        return (
            order.orderId,
            order.buyer,
            order.totalAmount,
            order.timestamp,
            order.status
        );
    }

    function getOrderItems(
        uint256 _orderId
    ) external view returns (OrderItem[] memory) {
        return orderItems[_orderId];
    }

    function getBuyerOrders(
        address _buyer
    ) external view returns (uint256[] memory) {
        return _buyerOrders[_buyer].values();
    }

    // Order Status Updates
    function updateOrderStatus(
        uint256 _orderId,
        OrderStatus _status
    ) external onlyRole(ORDER_MANAGER_ROLE) {
        require(_orderId < _orderIds.current(), "Invalid orderId");
        orders[_orderId].status = _status;
        emit OrderStatusUpdated(_orderId, _status);
    }

    // Refunds (Simplified)
    function refundOrder(
        uint256 _orderId
    ) external onlyRole(REFUND_MANAGER_ROLE) {
        require(_orderId < _orderIds.current(), "Invalid orderId");
        Order storage order = orders[_orderId];
        require(
            order.status == OrderStatus.Placed ||
                order.status == OrderStatus.Delivered ||
                order.status == OrderStatus.Dispute,
            "Not refundable"
        );

        uint256 refundAmount = order.totalAmount; // Full refund
        order.status = OrderStatus.Refunded;

        bool success = token.transfer(order.buyer, refundAmount); // Refund from contract
        require(success, "Refund failed");

        emit OrderRefunded(_orderId, order.buyer, refundAmount);
    }

    // Owner Functions - Example
    function withdrawTokens(
        address _to,
        uint256 _amount
    ) external onlyRole(OWNER_ROLE) {
        require(
            _amount <= token.balanceOf(address(this)),
            "Insufficient contract balance"
        );
        bool success = token.transfer(_to, _amount);
        require(success, "Withdrawal failed");
    }
}
