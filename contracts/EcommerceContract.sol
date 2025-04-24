// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./lib/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract SecureEcommerce is ReentrancyGuard, AccessControl, Pausable {
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
        uint256 price;
        address vendor;
        uint256 stock;
        bool exists;
    }

    struct OrderItem {
        uint256 productId;
        uint256 quantity;
        uint256 price;
    }

    struct Order {
        uint256 orderId;
        address buyer;
        uint256 totalAmount;
        uint256 timestamp;
        OrderStatus status;
        bool fundsReleased;
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
    mapping(uint256 => OrderItem[]) public orderItems;
    mapping(address => EnumerableSet.UintSet) private _buyerOrders;
    mapping(uint256 => mapping(address => uint256)) public vendorEscrow;
    mapping(address => uint256) public pendingWithdrawals;

    event ProductAdded(
        uint256 indexed productId,
        address vendor,
        uint256 price,
        uint256 stock
    );
    event ProductUpdated(
        uint256 indexed productId,
        uint256 price,
        uint256 stock
    );
    event ProductRemoved(uint256 indexed productId);
    event OrderPlaced(
        uint256 indexed orderId,
        address buyer,
        uint256 totalAmount,
        uint256 timestamp
    );
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
    event OrderRefunded(uint256 indexed orderId, address buyer, uint256 amount);
    event FundsReleased(uint256 indexed orderId);
    event Withdrawal(address vendor, uint256 amount);

    constructor(address _token) {
        require(_token != address(0), "Invalid token");
        token = IERC20(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyVendor() {
        require(hasRole(VENDOR_ROLE, msg.sender), "Not a vendor");
        _;
    }

    // Product Logic (only ID, price, stock — metadata off-chain)
    function addProduct(uint256 _price, uint256 _stock) external onlyVendor {
        require(_price > 0 && _stock > 0, "Invalid price/stock");

        _productIds.increment();
        uint256 productId = _productIds.current();

        products[productId] = Product({
            productId: productId,
            price: _price,
            vendor: msg.sender,
            stock: _stock,
            exists: true
        });

        _vendorProducts[msg.sender].add(productId);
        emit ProductAdded(productId, msg.sender, _price, _stock);
    }

    function updateProduct(
        uint256 _productId,
        uint256 _price,
        uint256 _stock
    ) external onlyVendor {
        Product storage product = products[_productId];
        require(product.exists && product.vendor == msg.sender, "Unauthorized");
        product.price = _price;
        product.stock = _stock;
        emit ProductUpdated(_productId, _price, _stock);
    }

    function removeProduct(uint256 _productId) external onlyVendor {
        Product storage product = products[_productId];
        require(product.exists && product.vendor == msg.sender, "Unauthorized");
        product.exists = false;
        _vendorProducts[msg.sender].remove(_productId);
        emit ProductRemoved(_productId);
    }

    // Order Logic
    function placeOrder(
        uint256[] calldata productIds,
        uint256[] calldata quantities
    ) external nonReentrant whenNotPaused returns (uint256 orderId) {
        require(
            productIds.length == quantities.length && productIds.length > 0,
            "Invalid input"
        );

        _orderIds.increment();
        orderId = _orderIds.current();

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < productIds.length; i++) {
            uint256 pid = productIds[i];
            uint256 qty = quantities[i];

            Product storage product = products[pid];
            require(product.exists && product.stock >= qty, "Unavailable");

            product.stock -= qty;
            uint256 cost = qty * product.price;
            totalAmount += cost;

            orderItems[orderId].push(OrderItem(pid, qty, product.price));
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
        require(_status != OrderStatus.Refunded, "Use refundOrder");
        orders[_orderId].status = _status;
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
            Product memory product = products[
                orderItems[_orderId][i].productId
            ];
            vendorEscrow[_orderId][product.vendor] = 0;
        }

        require(
            token.transfer(order.buyer, order.totalAmount),
            "Refund failed"
        );
        emit OrderRefunded(_orderId, order.buyer, order.totalAmount);
    }
}
