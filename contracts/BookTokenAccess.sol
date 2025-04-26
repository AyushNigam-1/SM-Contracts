// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract BookTokenAccess is AccessControl, ReentrancyGuard {
    bytes32 public constant BOOK_MANAGER_ROLE = keccak256("BOOK_MANAGER_ROLE");

    struct Book {
        uint256 tokenCost;
        bool exists;
    }

    IERC20 public immutable accessToken;

    mapping(uint256 => Book) public books;
    mapping(address => mapping(uint256 => bool)) public accessRegistry;

    event BookAdded(uint256 bookId, uint256 cost);
    event BookUpdated(uint256 bookId, uint256 newCost);
    event BookDeleted(uint256 bookId);
    event AccessGranted(address indexed user, uint256 bookId);
    event TokensWithdrawn(address to, uint256 amount);

    constructor(address _token) {
        require(_token != address(0), "Invalid token");
        accessToken = IERC20(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(BOOK_MANAGER_ROLE, msg.sender);
    }

    modifier onlyManager() {
        require(hasRole(BOOK_MANAGER_ROLE, msg.sender), "Not book manager");
        _;
    }

    function addBook(uint256 bookId, uint256 cost) external onlyManager {
        require(!books[bookId].exists, "Book already exists");
        require(cost > 0, "Invalid cost");

        books[bookId] = Book(cost, true);
        emit BookAdded(bookId, cost);
    }

    function updateBook(uint256 bookId, uint256 newCost) external onlyManager {
        require(books[bookId].exists, "Book not found");
        require(newCost > 0, "Invalid cost");

        books[bookId].tokenCost = newCost;
        emit BookUpdated(bookId, newCost);
    }

    function deleteBook(uint256 bookId) external onlyManager {
        require(books[bookId].exists, "Book not found");
        delete books[bookId];
        emit BookDeleted(bookId);
    }

    function unlockBook(uint256 bookId) external nonReentrant {
        Book memory book = books[bookId];
        require(book.exists, "Invalid book");
        require(!accessRegistry[msg.sender][bookId], "Already unlocked");

        require(
            accessToken.transferFrom(msg.sender, address(this), book.tokenCost),
            "Payment failed"
        );

        accessRegistry[msg.sender][bookId] = true;
        emit AccessGranted(msg.sender, bookId);
    }

    function hasAccess(
        address user,
        uint256 bookId
    ) external view returns (bool) {
        return accessRegistry[user][bookId];
    }

    function withdrawTokens(
        address to,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Zero address");
        require(accessToken.transfer(to, amount), "Withdraw failed");
        emit TokensWithdrawn(to, amount);
    }
}
