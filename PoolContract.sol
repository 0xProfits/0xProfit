// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract TokenPool {
    address public owner;
    IERC20 public token;

    uint256 public poolFee = 10;        // 10% fee
    uint256 public poolTimeLimit = 30; // 30-second timer limit
    uint256 public maxTransferLimit = 15 * 10 ** 10; // Maximum 15 tokens, assuming 18 decimals

    struct Pool {
        address[] players;
        uint256 startTime;
        bool started;
        uint256 totalAmount;
    }

    mapping(uint256 => Pool) public pools;

    // ✅ Store last winner per pool type
    mapping(uint256 => address) public lastWinner;

    // Events
    event Joined(uint256 indexed poolType, address indexed player, uint256 amount);
    event Refunded(uint256 indexed poolType, address indexed player, uint256 amount);
    event Won(uint256 indexed poolType, address indexed winner, uint256 prize);
    event FeeTaken(uint256 indexed poolType, address indexed owner, uint256 fee);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier maxTransferLimitCheck(uint256 amount) {
        require(amount <= maxTransferLimit, "Exceeds maximum transfer limit of 15 tokens");
        _;
    }

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Zero token address");
        token = IERC20(_tokenAddress);
        owner = msg.sender;
    }

    // Join a pool by depositing tokens
    function joinPool(uint256 poolType, uint256 amount) external maxTransferLimitCheck(amount) {
        require(amount > 0, "Amount>0");
        // Transfer tokens from user to contract
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");

        Pool storage p = pools[poolType];
        p.players.push(msg.sender);
        p.totalAmount += amount;

        // Start timer when the second player joins
        if (p.players.length == 2) {
            p.startTime = block.timestamp;
            p.started = true;
        }

        emit Joined(poolType, msg.sender, amount);
    }

    // Finalize the pool after the timer ends, selecting a winner or refunding
    function finalizePool(uint256 poolType) external {
        Pool storage p = pools[poolType];
        require(p.started, "Not started");
        require(block.timestamp >= p.startTime + poolTimeLimit, "Timer not up");

        uint256 count = p.players.length;
        uint256 total = p.totalAmount;

        if (count == 1) {
            // Refund the only player
            address sole = p.players[0];
            uint256 refundAmt = total;
            delete pools[poolType];
            require(token.transfer(sole, refundAmt), "refund failed");
            emit Refunded(poolType, sole, refundAmt);
        } else {
            // Pick a random winner
            uint256 idx = randomWinner(poolType, count);
            address winner = p.players[idx];

            // ✅ store the winner
            lastWinner[poolType] = winner;

            uint256 fee = (total * poolFee) / 100;
            uint256 prize = total - fee;

            delete pools[poolType];
            require(token.transfer(winner, prize), "prize transfer failed");
            require(token.transfer(owner, fee), "fee transfer failed");

            emit Won(poolType, winner, prize);
            emit FeeTaken(poolType, owner, fee);
        }
    }

    // Pseudo-random winner selection (updated for post-Paris upgrade)
    function randomWinner(uint256 poolType, uint256 count) internal view returns (uint256) {
        Pool storage p = pools[poolType];
        return uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, p.players)
            )
        ) % count;
    }

    // Update the fee percentage (max 10%)
    function updateFee(uint256 newFee) external onlyOwner {
        require(newFee <= 10, "Fee>10%");
        poolFee = newFee;
    }

    // Update the time limit for pool (min 10 seconds)
    function updateTimeLimit(uint256 newTime) external onlyOwner {
        require(newTime >= 10, "Too short");
        poolTimeLimit = newTime;
    }

    // View the players in a given pool
    function getPlayers(uint256 poolType) external view returns (address[] memory) {
        return pools[poolType].players;
    }

    // (OPTIONAL) Get last winner address (explicit getter)
    function getLastWinner(uint256 poolType) external view returns (address) {
        return lastWinner[poolType];
    }
}
