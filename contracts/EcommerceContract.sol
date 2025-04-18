// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract EcommerceContract {
    address public owner;
    IERC20 public token;

    enum OrderStatus { Placed, Delivered, Refunded, Cancelled }

    struct Order {
        uint256 orderId;
        address buyer;
        address vendor;
        uint256 amount;
        OrderStatus status;
        uint256 timestamp;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    event OrderPlaced(uint256 indexed orderId, address indexed buyer, address indexed vendor, uint256 amount, uint256 timestamp);
    event OrderStatusUpdated(uint256 indexed orderId, OrderStatus status);
    event OrderRefunded(uint256 indexed orderId, address indexed buyer, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _tokenAddress) {
        owner = msg.sender;
        token = IERC20(_tokenAddress);
    }

    function placeOrder(address vendor, uint256 amount) external {
        require(vendor != address(0), "Invalid vendor");
        require(amount > 0, "Amount must be > 0");

        bool success = token.transferFrom(msg.sender, vendor, amount);
        require(success, "Token transfer failed");

        orders[nextOrderId] = Order({
            orderId: nextOrderId,
            buyer: msg.sender,
            vendor: vendor,
            amount: amount,
            status: OrderStatus.Placed,
            timestamp: block.timestamp
        });

        emit OrderPlaced(nextOrderId, msg.sender, vendor, amount, block.timestamp);
        nextOrderId++;
    }

    function updateOrderStatus(uint256 orderId, OrderStatus newStatus) external onlyOwner {
        require(orderId < nextOrderId, "Invalid orderId");
        orders[orderId].status = newStatus;
        emit OrderStatusUpdated(orderId, newStatus);
    }

    function refund(uint256 orderId) external onlyOwner {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.Placed || order.status == OrderStatus.Delivered, "Not refundable");

        order.status = OrderStatus.Refunded;

        bool success = token.transferFrom(order.vendor, order.buyer, order.amount);
        require(success, "Refund failed");

        emit OrderRefunded(orderId, order.buyer, order.amount);
    }

    function getOrder(uint256 orderId) external view returns (
        address buyer,
        address vendor,
        uint256 amount,
        OrderStatus status,
        uint256 timestamp
    ) {
        require(orderId < nextOrderId, "Invalid orderId");
        Order memory o = orders[orderId];
        return (o.buyer, o.vendor, o.amount, o.status, o.timestamp);
    }
}
