// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TokenAccess is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    IERC20 public immutable token;
    uint256 public accessFee;

    struct Access {
        address user;
        string bookId;
        uint256 timestamp;
    }

    mapping(address => mapping(string => bool)) public hasAccess;
    Access[] public accessLog;

    event AccessGranted(address indexed user, string bookId, uint256 timestamp);
    event AccessFeeUpdated(uint256 newFee);
    event TokenWithdrawn(address to, uint256 amount);

    constructor(address _token, uint256 _accessFee) {
        require(_token != address(0), "Invalid token");
        require(_accessFee > 0, "Fee must be > 0");

        token = IERC20(_token);
        accessFee = _accessFee;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function unlock(string calldata bookId) external nonReentrant {
        require(!hasAccess[msg.sender][bookId], "Already unlocked");

        bool success = token.transferFrom(msg.sender, address(this), accessFee);
        require(success, "Token transfer failed");

        hasAccess[msg.sender][bookId] = true;
        accessLog.push(Access(msg.sender, bookId, block.timestamp));

        emit AccessGranted(msg.sender, bookId, block.timestamp);
    }

    function checkAccess(
        address user,
        string calldata bookId
    ) external view returns (bool) {
        return hasAccess[user][bookId];
    }

    function setAccessFee(uint256 newFee) external onlyRole(ADMIN_ROLE) {
        require(newFee > 0, "Invalid fee");
        accessFee = newFee;
        emit AccessFeeUpdated(newFee);
    }

    function withdrawTokens(
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "Invalid address");
        require(token.transfer(to, amount), "Transfer failed");
        emit TokenWithdrawn(to, amount);
    }

    function getAccessLogLength() external view returns (uint256) {
        return accessLog.length;
    }

    function getAccessLog(
        uint256 index
    ) external view returns (address, string memory, uint256) {
        Access memory entry = accessLog[index];
        return (entry.user, entry.bookId, entry.timestamp);
    }
}
