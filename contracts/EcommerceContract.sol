// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
// import "@openzeppelin/contracts/security/Pausable.sol";
import "./lib/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract SecureEcommerce is ReentrancyGuard, AccessControl {
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    bytes32 public constant VENDOR_ROLE = keccak256("VENDOR_ROLE");
    bytes32 public constant ORDER_MANAGER_ROLE =
        keccak256("ORDER_MANAGER_ROLE");
    bytes32 public constant REFUND_MANAGER_ROLE =
        keccak256("REFUND_MANAGER_ROLE");

    IERC20 public immutable token;

    Counters.Counter private _productIds;
    Counters.Counter private _orderIds;

    struct Product {
        uint256 productId;
        string name;
        string description;
        string image;
        uint256 price;
        address vendor;
        uint256 stock;
        bool exists;
    }

    struct Order {
        uint256 orderId;
        address buyer;
        uint256 totalAmount;
        uint256 timestamp;
        OrderStatus status;
        bool fundsReleased;
    }

    struct OrderItem {
        uint256 productId;
        uint256 quantity;
        uint256 price;
    }

    enum OrderStatus {
        Placed,
        Shipped,
        Delivered,
        Completed,
        Refunded,
        Cancelled,
        Dispute
    }

    mapping(uint256 => Product) public products;
    mapping(address => EnumerableSet.UintSet) private _vendorProducts;
    mapping(uint256 => Order) public orders;
    mapping(address => EnumerableSet.UintSet) private _buyerOrders;
    mapping(uint256 => OrderItem[]) public orderItems;
    mapping(uint256 => mapping(address => uint256)) public vendorEscrow;
    mapping(address => uint256) public pendingWithdrawals;

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
    event Withdrawal(address vendor, uint256 amount);
    event FundsReleased(uint256 orderId);
    event Paused(address account);
    event Unpaused(address account);

    constructor(address _token) {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyVendor() {
        require(hasRole(VENDOR_ROLE, msg.sender), "Not a vendor");
        _;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function addProduct(
        string memory _name,
        string memory _description,
        string memory _image,
        uint256 _price,
        uint256 _stock
    ) external onlyVendor whenNotPaused {
        require(_price > 0 && _stock > 0, "Invalid price or stock");
        require(bytes(_name).length > 0, "Name required");

        _productIds.increment();
        uint256 productId = _productIds.current();

        products[productId] = Product({
            productId: productId,
            name: _name,
            description: _description,
            image: _image,
            price: _price,
            vendor: msg.sender,
            stock: _stock,
            exists: true
        });

        _vendorProducts[msg.sender].add(productId);
        emit ProductAdded(productId, _name, msg.sender, _price, _stock);
    }

    function updateProduct(
        uint256 _productId,
        string memory _name,
        uint256 _price,
        uint256 _stock
    ) external onlyVendor whenNotPaused {
        Product storage product = products[_productId];
        require(product.exists && product.vendor == msg.sender, "Unauthorized");
        product.name = _name;
        product.price = _price;
        product.stock = _stock;
        emit ProductUpdated(_productId, _name, _price, _stock);
    }

    function removeProduct(
        uint256 _productId
    ) external onlyVendor whenNotPaused {
        Product storage product = products[_productId];
        require(product.exists && product.vendor == msg.sender, "Unauthorized");
        product.exists = false;
        _vendorProducts[msg.sender].remove(_productId);
        emit ProductRemoved(_productId);
    }

    function getAllProducts() external view returns (Product[] memory) {
        uint256 count = _productIds.current();
        Product[] memory all = new Product[](count);
        for (uint256 i = 1; i <= count; i++) {
            all[i - 1] = products[i];
        }
        return all;
    }

    function placeOrder(
        uint256[] calldata _productIds,
        uint256[] calldata _quantities
    ) external nonReentrant whenNotPaused returns (uint256 orderId) {
        require(
            _productIds.length == _quantities.length && _productIds.length > 0,
            "Invalid input"
        );

        _orderIds.increment();
        orderId = _orderIds.current();
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < _productIds.length; i++) {
            uint256 pid = _productIds[i];
            Product storage product = products[pid];
            require(
                product.exists && product.stock >= _quantities[i],
                "Invalid product"
            );

            product.stock -= _quantities[i];
            uint256 cost = _quantities[i] * product.price;
            totalAmount += cost;

            orderItems[orderId].push(
                OrderItem(pid, _quantities[i], product.price)
            );
            vendorEscrow[orderId][product.vendor] += cost;
        }

        require(
            token.transferFrom(msg.sender, address(this), totalAmount),
            "Payment failed"
        );

        orders[orderId] = Order({
            orderId: orderId,
            buyer: msg.sender,
            totalAmount: totalAmount,
            timestamp: block.timestamp,
            status: OrderStatus.Placed,
            fundsReleased: false
        });

        _buyerOrders[msg.sender].add(orderId);
        emit OrderPlaced(orderId, msg.sender, totalAmount, block.timestamp);
    }

    function releaseFunds(
        uint256 _orderId
    ) external onlyRole(ORDER_MANAGER_ROLE) {
        Order storage order = orders[_orderId];
        require(order.status == OrderStatus.Completed, "Order not completed");
        require(!order.fundsReleased, "Funds already released");

        order.fundsReleased = true;

        for (uint256 i = 0; i < orderItems[_orderId].length; i++) {
            OrderItem memory item = orderItems[_orderId][i];
            Product memory product = products[item.productId];
            uint256 amount = item.quantity * item.price;

            if (vendorEscrow[_orderId][product.vendor] > 0) {
                pendingWithdrawals[product.vendor] += amount;
                vendorEscrow[_orderId][product.vendor] = 0;
            }
        }

        emit FundsReleased(_orderId);
    }

    function withdrawPayout() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        require(amount > 0, "No funds");
        pendingWithdrawals[msg.sender] = 0;
        require(token.transfer(msg.sender, amount), "Withdraw failed");
        emit Withdrawal(msg.sender, amount);
    }

    function updateOrderStatus(
        uint256 _orderId,
        OrderStatus _status
    ) external onlyRole(ORDER_MANAGER_ROLE) {
        Order storage order = orders[_orderId];
        require(_status != OrderStatus.Refunded, "Use refundOrder for refunds");
        order.status = _status;
        emit OrderStatusUpdated(_orderId, _status);
    }

    function refundOrder(
        uint256 _orderId
    ) external onlyRole(REFUND_MANAGER_ROLE) nonReentrant {
        Order storage order = orders[_orderId];
        require(
            order.status == OrderStatus.Placed ||
                order.status == OrderStatus.Shipped ||
                order.status == OrderStatus.Dispute,
            "Can't refund"
        );
        require(!order.fundsReleased, "Funds already released");

        order.status = OrderStatus.Refunded;

        for (uint256 i = 0; i < orderItems[_orderId].length; i++) {
            OrderItem memory item = orderItems[_orderId][i];
            Product memory product = products[item.productId];
            if (vendorEscrow[_orderId][product.vendor] > 0) {
                vendorEscrow[_orderId][product.vendor] = 0;
            }
        }

        require(
            token.transfer(order.buyer, order.totalAmount),
            "Refund failed"
        );
        emit OrderRefunded(_orderId, order.buyer, order.totalAmount);
    }
}
