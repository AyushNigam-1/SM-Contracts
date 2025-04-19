// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract KnowledgeToken {
    string public name = "Knowledge Token";
    string public symbol = "KNW";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    address public owner;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed burner, uint256 amount);

    constructor(uint256 initialSupply, address treasury) {
        require(treasury != address(0), "Invalid treasury address");
        owner = msg.sender;
        mint(treasury, initialSupply); // mint initial tokens to treasury
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(to != address(0), "Zero address");
        require(balanceOf[msg.sender] >= value, "Insufficient balance");

        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        require(spender != address(0), "Zero address");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool) {
        require(to != address(0), "Zero address");
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");

        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Zero address");
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Mint(to, amount);
        emit Transfer(address(0), to, amount);
    }

    function updateOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        owner = newOwner;
    }

    // Burn function (owner only)
    function burn(uint256 amount) external onlyOwner {
        require(
            balanceOf[msg.sender] >= amount,
            "Insufficient balance to burn"
        );

        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;

        emit Burn(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount); // Emit transfer to address(0)
    }

    // Burn function (approved users)
    function burnFrom(address from, uint256 amount) external {
        require(allowance[from][msg.sender] >= amount, "Allowance too low");
        require(balanceOf[from] >= amount, "Insufficient balance");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        totalSupply -= amount;

        emit Burn(from, amount);
        emit Transfer(from, address(0), amount); // Emit transfer to address(0)
    }
}
